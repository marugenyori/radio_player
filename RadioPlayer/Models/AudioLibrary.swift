import Foundation

/// 見つかった音声ファイル
struct AudioFile: Sendable {
    let url: URL
    /// iCloud 上にあって、まだ iPhone にダウンロードされていなければ false
    let isDownloaded: Bool
    /// アプリの書類フォルダ（iPhone の中）にあれば true。iCloud から消えても再生できる
    let isLocal: Bool
    /// ファイル名の「120 タイトル.mp3」のタイトル部分（なければ空）
    let titleFromName: String

    var priority: Int { isLocal ? 2 : isDownloaded ? 1 : 0 }
}

/// フォルダの中から音声ファイルを探し、番組と回番号を割り出す
enum AudioLibrary {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav"]

    /// 探した結果。files は Episode.key で引ける形、report は設定画面に出す説明
    struct ScanResult: Sendable {
        var files: [String: AudioFile] = [:]
        var report: [String] = []
    }

    static func scan(roots: [(name: String, url: URL, isLocal: Bool)]) -> ScanResult {
        var result = ScanResult()
        for root in roots {
            var fileCount = 0
            var audioCount = 0
            var matched = 0
            var samples: [String] = []
            walk(root.url, depth: 0) { url in
                fileCount += 1
                if samples.count < 3 { samples.append(url.lastPathComponent) }
                guard let file = audioFile(at: url, isLocal: root.isLocal) else { return }
                audioCount += 1
                guard let id = identify(url: file.url) else { return }
                matched += 1
                let key = Episode.key(id.show, id.number)
                // 同じ回が2つあれば、iPhone の中 → ダウンロード済み → 未ダウンロード の順に優先する
                if let existing = result.files[key], existing.priority >= file.priority { return }
                result.files[key] = file
            }
            var line = "\(root.name)：ファイル \(fileCount) 個、音声 \(audioCount) 個、回番号あり \(matched) 個"
            if !samples.isEmpty { line += "（例：\(samples.joined(separator: "、"))）" }
            result.report.append(line)
        }
        return result
    }

    /// フォルダの中をたどる。iCloud のフォルダは一覧がまだ届いていないことがあるので、
    /// 中身はダウンロードせずに一覧だけ取り寄せてから読む
    private static func walk(_ directory: URL, depth: Int, visit: (URL) -> Void) {
        guard depth < 5 else { return }
        var coordinatorError: NSError?
        var children: [URL] = []
        NSFileCoordinator().coordinate(readingItemAt: directory, options: .immediatelyAvailableMetadataOnly, error: &coordinatorError) { url in
            children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
            )) ?? []
        }
        if children.isEmpty {
            children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        }
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // coordinate の中で受け取った URL は別の場所を指すことがあるので、元のフォルダの下に付け直す
            let url = directory.appending(path: child.lastPathComponent)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                walk(url, depth: depth + 1, visit: visit)
            } else {
                visit(url)
            }
        }
    }

    /// 番組と回番号。数字で始まらないファイルは nil
    static func identify(url: URL) -> (show: Show, number: Int)? {
        let digits = url.lastPathComponent.prefix { $0.isASCII && $0.isNumber }
        guard let number = Int(digits), number > 0 else { return nil }
        let path = url.path
        let show: Show = path.localizedCaseInsensitiveContains("saikou") || path.contains("最高") ? .saikou : .kinyo
        return (show, number)
    }

    /// iCloud 上のファイルなら、ダウンロードが終わるまで待つ
    static func prepare(_ file: AudioFile) async throws -> URL {
        if file.isDownloaded { return file.url }
        let url = file.url
        return try await Task.detached(priority: .userInitiated) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var coordinatorError: NSError?
            // 読み取りの調整を頼むと、ダウンロードが終わるまで待ってからブロックが呼ばれる
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { _ in }
            if let coordinatorError { throw coordinatorError }
            return url
        }.value
    }

    private static func audioFile(at url: URL, isLocal: Bool) -> AudioFile? {
        var name = url.lastPathComponent
        var realURL = url
        var isPlaceholder = false

        if name.hasPrefix(".") {
            // 「.001.mp3.icloud」→「001.mp3」
            guard name.hasSuffix(".icloud") else { return nil }
            name = String(name.dropFirst().dropLast(".icloud".count))
            realURL = url.deletingLastPathComponent().appending(path: name)
            isPlaceholder = true
        }
        guard audioExtensions.contains((name as NSString).pathExtension.lowercased()) else { return nil }

        var downloaded = !isPlaceholder
        if downloaded,
           let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true,
           let status = values.ubiquitousItemDownloadingStatus {
            downloaded = status == .current
        }

        return AudioFile(url: realURL, isDownloaded: downloaded, isLocal: isLocal, titleFromName: titleFromName(name))
    }

    /// 「120 タイトル.mp3」「120_タイトル.mp3」からタイトルを取り出す。「001kaime.mp3」のように区切りがなければ空
    private static func titleFromName(_ name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        let rest = stem.drop { $0.isASCII && $0.isNumber }
        guard let first = rest.first, first.isWhitespace || first == "_" || first == "-" else { return "" }
        return rest.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "_-")))
    }
}
