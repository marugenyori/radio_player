import Foundation

/// 見つかった音声ファイル
struct AudioFile: Sendable {
    let url: URL
    /// iCloud 上にあって、まだ iPhone にダウンロードされていなければ false
    let isDownloaded: Bool
    /// ファイル名の「120 タイトル.mp3」のタイトル部分（なければ空）
    let titleFromName: String
}

/// フォルダの中から音声ファイルを探し、番組と回番号を割り出す
enum AudioLibrary {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav"]

    /// 見つかったファイルを Episode.key で引ける形で返す
    static func scan(roots: [URL]) -> [String: AudioFile] {
        var found: [String: AudioFile] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]

        for root in roots {
            // 隠しファイルも見る（iCloud の未ダウンロードのファイルは「.名前.mp3.icloud」になるため）
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { continue }
            for case let url as URL in enumerator {
                guard let file = audioFile(at: url),
                      let id = identify(url: file.url) else { continue }
                let key = Episode.key(id.show, id.number)
                // 同じ回が2つあれば、ダウンロード済みのほうを使う
                if let existing = found[key], existing.isDownloaded || !file.isDownloaded { continue }
                found[key] = file
            }
        }
        return found
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

    private static func audioFile(at url: URL) -> AudioFile? {
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

        return AudioFile(url: realURL, isDownloaded: downloaded, titleFromName: titleFromName(name))
    }

    /// 「120 タイトル.mp3」「120_タイトル.mp3」からタイトルを取り出す。「001kaime.mp3」のように区切りがなければ空
    private static func titleFromName(_ name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        let rest = stem.drop { $0.isASCII && $0.isNumber }
        guard let first = rest.first, first.isWhitespace || first == "_" || first == "-" else { return "" }
        return rest.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "_-")))
    }
}
