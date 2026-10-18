import Foundation

/// iCloud Drive のフォルダにある音声を、iPhone の中（アプリの書類フォルダ）にコピーする。
/// コピーした回は電波がなくても再生でき、iCloud 側の一時的なコピーは消して容量を二重に使わない
@MainActor
final class Downloader: ObservableObject {
    enum DownloadError: LocalizedError {
        case diskFull

        var errorDescription: String? { "iPhone の空き容量が足りません。" }
    }

    @Published private(set) var current: Episode?
    @Published private(set) var remaining = 0
    @Published private(set) var errorMessage: String?
    @Published var autoDownload: Bool {
        didSet {
            UserDefaults.standard.set(autoDownload, forKey: "autoDownload")
            if autoDownload { start() }
        }
    }

    private let library: Library
    private var task: Task<Void, Never>?
    private var failed: Set<String> = []

    /// コピー先に残す空き容量（これを下回りそうなら止める）
    nonisolated private static let reserveBytes: Int64 = 1_000_000_000

    init(library: Library) {
        self.library = library
        autoDownload = UserDefaults.standard.object(forKey: "autoDownload") as? Bool ?? true
    }

    var isRunning: Bool { task != nil }

    /// 自動ダウンロードがオンなら始める（探し終わったときに呼ばれる）
    func startIfAuto() {
        if autoDownload { start() }
    }

    /// iPhone の中にない回を、古い順に1本ずつダウンロードする
    func start() {
        guard task == nil else { return }
        errorMessage = nil
        failed = []
        task = Task {
            await run()
            task = nil
            current = nil
            remaining = library.episodesToDownload.count
        }
    }

    func stop() {
        task?.cancel()
    }

    private func run() async {
        while !Task.isCancelled {
            let targets = library.episodesToDownload.filter { !failed.contains($0.id) }
            remaining = targets.count
            guard let episode = targets.first, let source = library.file(for: episode) else { return }
            current = episode
            do {
                let url = try await Self.copy(source, show: episode.show)
                library.addLocalFile(url, for: episode)
            } catch DownloadError.diskFull {
                errorMessage = DownloadError.diskFull.localizedDescription
                return
            } catch {
                failed.insert(episode.id)
                errorMessage = "\(episode.show.name) \(episode.numberLabel)：\(error.localizedDescription)"
            }
        }
    }

    /// iCloud からダウンロードを待ってコピーし、iCloud 側の一時的なコピーを消す
    nonisolated private static func copy(_ source: AudioFile, show: Show) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let folder = URL.documentsDirectory.appending(path: show == .saikou ? "saikou_radio_mp3" : "kinyo_radio_mp3")
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appending(path: source.url.lastPathComponent)

            try? fileManager.startDownloadingUbiquitousItem(at: source.url)
            var coordinatorError: NSError?
            var copyError: Error?
            // 読み取りの調整を頼むと、ダウンロードが終わるまで待ってからブロックが呼ばれる
            NSFileCoordinator().coordinate(readingItemAt: source.url, options: [], error: &coordinatorError) { url in
                do {
                    let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    let free = (try? URL.documentsDirectory.resourceValues(
                        forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                    ).volumeAvailableCapacityForImportantUsage) ?? Int64.max
                    if size + reserveBytes > free { throw DownloadError.diskFull }

                    // 途中で止まっても壊れたファイルが残らないよう、隠しファイルにコピーしてから名前を変える
                    let partial = folder.appending(path: ".\(UUID().uuidString).part")
                    try fileManager.copyItem(at: url, to: partial)
                    if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.moveItem(at: partial, to: destination)
                } catch {
                    copyError = error
                }
            }
            if let coordinatorError { throw coordinatorError }
            if let copyError { throw copyError }
            try? fileManager.evictUbiquitousItem(at: source.url)
            return destination
        }.value
    }
}
