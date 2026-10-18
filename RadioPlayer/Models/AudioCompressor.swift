import AVFoundation

/// iPhone の中の音声を、しゃべり向けの小さい形式（モノラル・48kbps の AAC）に変換する
enum AudioCompressor {
    /// 変換の終わりを、専用のキューの中だけで覚えておく
    private final class FinishFlag: @unchecked Sendable {
        var finished = false
    }

    static let bitRate = 48_000
    private static let sampleRate = 44_100

    enum CompressError: LocalizedError {
        case noAudio
        case failed

        var errorDescription: String? {
            switch self {
            case .noAudio: "音声が入っていないファイルです。"
            case .failed: "変換に失敗しました。"
            }
        }
    }

    /// 変換して元のファイルを消し、新しいファイルの場所を返す。
    /// もともと小さい、または変換しても小さくならないときは何もせず nil を返す
    static func compress(_ source: URL) async throws -> URL? {
        guard source.pathExtension.lowercased() != "m4a" else { return nil }
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw CompressError.noAudio }
        let dataRate = try await track.load(.estimatedDataRate)
        if dataRate > 0, dataRate <= Float(bitRate) * 1.3 { return nil }

        let folder = source.deletingLastPathComponent()
        // 途中で止まっても壊れたファイルが残らないよう、隠しファイルに書いてから名前を変える
        let partial = folder.appending(path: ".\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: partial) }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: partial, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else { throw writer.error ?? reader.error ?? CompressError.failed }
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let state = FinishFlag()
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "AudioCompressor")) {
                while input.isReadyForMoreMediaData, !state.finished {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        if !input.append(buffer) {
                            reader.cancelReading()
                        } else {
                            continue
                        }
                    }
                    state.finished = true
                    input.markAsFinished()
                    continuation.resume()
                }
            }
        }
        await writer.finishWriting()

        guard reader.status == .completed, writer.status == .completed else {
            throw writer.error ?? reader.error ?? CompressError.failed
        }

        let fileManager = FileManager.default
        let oldSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let newSize = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard newSize > 0, Double(newSize) < Double(oldSize) * 0.9 else { return nil }

        let destination = source.deletingPathExtension().appendingPathExtension("m4a")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: partial, to: destination)
        try fileManager.removeItem(at: source)
        return destination
    }
}
