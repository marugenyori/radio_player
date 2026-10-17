import SwiftUI

/// 画面下の小さな再生バー。タップで再生画面を開く
struct MiniPlayerBar: View {
    @EnvironmentObject private var player: AudioPlayer
    let open: () -> Void

    var body: some View {
        if let episode = player.current {
            VStack(spacing: 0) {
                ProgressView(value: progress)
                    .tint(.accentColor)
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(episode.show.name) \(episode.numberLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(episode.displayTitle)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if player.isLoading {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(player.isPlaying ? "一時停止" : "再生")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .background(.bar)
        }
    }

    private var progress: Double {
        player.duration > 0 ? min(1, player.currentTime / player.duration) : 0
    }
}
