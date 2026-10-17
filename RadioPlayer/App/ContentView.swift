import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var showsPlayer = false

    var body: some View {
        NavigationStack {
            EpisodeListView()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.current != nil {
                MiniPlayerBar { showsPlayer = true }
            }
        }
        .sheet(isPresented: $showsPlayer) {
            PlayerView()
        }
        .alert("再生できませんでした", isPresented: errorShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )
    }
}
