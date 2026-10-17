import Foundation

/// 回番号とタイトルの一覧（episodes.json）を読み込む。
/// 設定画面から新しい JSON を読み込んだときは Application Support に置いたものを優先する。
enum EpisodeCatalog {
    struct Entry: Codable {
        let show: Show
        let number: Int
        let title: String
    }

    enum ImportError: LocalizedError {
        case empty

        var errorDescription: String? { "一覧が空です。episodes.json の形式を確認してください。" }
    }

    static var customURL: URL {
        URL.applicationSupportDirectory.appending(path: "episodes.json")
    }

    static var usesCustom: Bool {
        FileManager.default.fileExists(atPath: customURL.path)
    }

    /// 番組ごとの [回番号: タイトル]
    static func load() -> [Show: [Int: String]] {
        if let titles = decode(at: customURL) { return titles }
        if let url = Bundle.main.url(forResource: "episodes", withExtension: "json"),
           let titles = decode(at: url) {
            return titles
        }
        return [:]
    }

    /// 選んだ JSON を確認してから保存する。読み込めた件数を返す。
    static func importJSON(from url: URL) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        guard !entries.isEmpty else { throw ImportError.empty }

        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try data.write(to: customURL, options: .atomic)
        return entries.count
    }

    static func resetToBundled() {
        try? FileManager.default.removeItem(at: customURL)
    }

    private static func decode(at url: URL) -> [Show: [Int: String]]? {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        var titles: [Show: [Int: String]] = [:]
        for entry in entries {
            titles[entry.show, default: [:]][entry.number] = entry.title
        }
        return titles
    }
}
