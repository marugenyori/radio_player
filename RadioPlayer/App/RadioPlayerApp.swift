import SwiftUI

@main
struct RadioPlayerApp: App {
    @StateObject private var store: ListeningStore
    @StateObject private var library = Library()
    @StateObject private var player: AudioPlayer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ListeningStore()
        _store = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: AudioPlayer(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(library)
                .environmentObject(player)
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
