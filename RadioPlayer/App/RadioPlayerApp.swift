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
        library.onScanned = { [weak downloader] in downloader?.startIfAuto() }
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
