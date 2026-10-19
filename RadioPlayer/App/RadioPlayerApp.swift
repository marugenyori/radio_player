import SwiftUI

@main
struct RadioPlayerApp: App {
    @StateObject private var store: ListeningStore
    @StateObject private var library: Library
    @StateObject private var player: AudioPlayer
    @StateObject private var downloader: Downloader
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ListeningStore()
        _store = StateObject(wrappedValue: store)
        let player = AudioPlayer(store: store)
        _player = StateObject(wrappedValue: player)
        let library = Library()
        let downloader = Downloader(library: library)
        downloader.playingEpisodeID = { [weak player] in player?.current?.id }
        player.nextEpisode = { [weak library] episode in
            guard let library, let next = library.next(after: episode), let file = library.file(for: next) else { return nil }
            return (next, file)
        }
        library.onScanned = { [weak downloader, weak library, weak player, weak store] in
            // 前回聴いていた回を、下の再生バーに出す
            if let library, let player, let id = store?.lastEpisodeID,
               let episode = Show.allCases.flatMap({ library.episodes(of: $0) }).first(where: { $0.id == id }),
               let file = library.file(for: episode) {
                player.restore(episode, file: file)
            }
            downloader?.startIfAuto()
        }
        _library = StateObject(wrappedValue: library)
        _downloader = StateObject(wrappedValue: downloader)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(downloader)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // PC からファイルを足したあとに戻ってきたときのため、毎回探し直す
                Task { await library.rescan() }
            case .inactive, .background:
                player.saveProgress()
            @unknown default:
                break
            }
        }
    }
}
