import Foundation

/// 一覧（タイトル）と、見つかった音声ファイルをまとめて持つ
@MainActor
final class Library: ObservableObject {
    @Published private(set) var episodesByShow: [Show: [Episode]] = [:]
    @Published private(set) var files: [String: AudioFile] = [:]
    @Published private(set) var isScanning = false
    /// 最後に探したときの様子（設定画面に出す）
    @Published private(set) var scanReport: [String] = []
    @Published private(set) var folderName: String?
    @Published private(set) var usesCustomCatalog = EpisodeCatalog.usesCustom

    private var titles: [Show: [Int: String]] = [:]
    private var folderURL: URL?
    /// 探している途中にもう一度頼まれたら、終わったあとにもう一度探す
    private var needsRescan = false
    private let bookmarkKey = "iCloudFolderBookmark"

    init() {
        titles = EpisodeCatalog.load()
        restoreFolder()
        rebuild()
    }

    func episodes(of show: Show) -> [Episode] {
        episodesByShow[show] ?? []
    }

    func file(for episode: Episode) -> AudioFile? {
        files[episode.id]
    }

    func fileCount(_ show: Show) -> Int {
        episodes(of: show).filter { files[$0.id] != nil }.count
    }

    var titledCount: Int {
        titles.values.reduce(0) { $0 + $1.values.filter { !$0.isEmpty }.count }
    }

    var catalogCount: Int {
        titles.values.reduce(0) { $0 + $1.count }
    }

    /// 次の回（音声があるものだけ）
    func next(after episode: Episode) -> Episode? {
        episodes(of: episode.show).first { $0.number > episode.number && files[$0.id] != nil }
    }

    // MARK: - ファイルを探す

    /// アプリの「書類」フォルダと、選んだ iCloud Drive のフォルダを探し直す
    func rescan() async {
        if isScanning {
            needsRescan = true
            return
        }
        isScanning = true
        repeat {
            needsRescan = false
            var roots: [(name: String, url: URL, isLocal: Bool)] = [("iPhone の中（アプリの書類フォルダ）", URL.documentsDirectory, true)]
            if let folderURL { roots.append(("選んだフォルダ「\(folderURL.lastPathComponent)」", folderURL, false)) }
            let scanRoots = roots
            let result = await Task.detached(priority: .userInitiated) {
                AudioLibrary.scan(roots: scanRoots)
            }.value
            files = result.files
            scanReport = result.report
            rebuild()
        } while needsRescan
        isScanning = false
        onScanned?()
    }

    /// 探し終わったときに呼ぶ（自動ダウンロードを始めるため）
    var onScanned: (@MainActor () -> Void)?

    /// iPhone の中にある回の数
    var localCount: Int { files.values.filter(\.isLocal).count }

    /// iPhone の中にまだない回（ダウンロードの対象）
    var episodesToDownload: [Episode] {
        Show.allCases.flatMap { episodes(of: $0) }.filter { files[$0.id].map { !$0.isLocal } ?? false }
    }

    /// ダウンロードが終わった回を、iPhone の中のファイルに差し替える
    func addLocalFile(_ url: URL, for episode: Episode) {
        let old = files[episode.id]
        files[episode.id] = AudioFile(url: url, isDownloaded: true, isLocal: true, titleFromName: old?.titleFromName ?? "")
        rebuild()
    }

    // MARK: - iCloud Drive のフォルダ

    func setFolder(_ url: URL) {
        stopAccessingFolder()
        // false が返っても読めることがあるので、そのまま進める
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url
        folderName = url.lastPathComponent
        // 次回以降もアクセスできるように覚えておく
        if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        Task { await rescan() }
    }

    func clearFolder() {
        stopAccessingFolder()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        Task { await rescan() }
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else { return }
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url
        folderName = url.lastPathComponent
        if isStale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
    }

    private func stopAccessingFolder() {
        folderURL?.stopAccessingSecurityScopedResource()
        folderURL = nil
        folderName = nil
    }

    // MARK: - タイトル一覧

    func importCatalog(from url: URL) throws -> Int {
        let count = try EpisodeCatalog.importJSON(from: url)
        reloadCatalog()
        return count
    }

    func resetCatalog() {
        EpisodeCatalog.resetToBundled()
        reloadCatalog()
    }

    private func reloadCatalog() {
        titles = EpisodeCatalog.load()
        usesCustomCatalog = EpisodeCatalog.usesCustom
        rebuild()
    }

    /// 1回〜最終回まで並べ、タイトルを入れる。タイトル不明ならファイル名のタイトルを使う
    private func rebuild() {
        var result: [Show: [Episode]] = [:]
        for show in Show.allCases {
            let showTitles = titles[show] ?? [:]
            let fileNumbers = files.values.compactMap { AudioLibrary.identify(url: $0.url) }.filter { $0.show == show }.map(\.number)
            let last = max(show.episodeCount, showTitles.keys.max() ?? 0, fileNumbers.max() ?? 0)
            result[show] = (1...last).map { number in
                var title = showTitles[number] ?? ""
                if title.isEmpty {
                    title = files[Episode.key(show, number)]?.titleFromName ?? ""
                }
                return Episode(show: show, number: number, title: title)
            }
        }
        episodesByShow = result
    }
}
