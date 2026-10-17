import SwiftUI

/// 再生画面
struct PlayerView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var store: ListeningStore
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    var body: some View {
        Group {
            if let episode = player.current {
                content(episode)
            } else {
                ContentUnavailableView("再生中の回はありません", systemImage: "radio")
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func content(_ episode: Episode) -> some View {
        let state = store.state(episode.id)
        return VStack(spacing: 20) {
            Spacer(minLength: 0)

            Image(systemName: "radio")
                .resizable()
                .scaledToFit()
                .frame(width: 110)
                .foregroundStyle(.tint)
                .padding(.bottom, 8)

            VStack(spacing: 6) {
                Text(episode.show.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(episode.numberLabel)
                    .font(.headline)
                Text(episode.displayTitle)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubTime : player.currentTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(player.duration, 1)
                ) { editing in
                    if editing {
                        scrubTime = player.currentTime
                        isScrubbing = true
                    } else {
                        player.seek(to: scrubTime)
                        isScrubbing = false
                    }
                }
                .disabled(player.isLoading)
                HStack {
                    Text(formatTime(shownTime))
                    Spacer()
                    if player.isLoading {
                        Text("読み込み中…")
                    }
                    Spacer()
                    Text("-" + formatTime(max(0, player.duration - shownTime)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 44) {
                Button {
                    player.skip(by: -AudioPlayer.skipBackSeconds)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                }
                .accessibilityLabel("15秒戻る")

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 72, height: 72)
                }
                .accessibilityLabel(player.isPlaying ? "一時停止" : "再生")

                Button {
                    player.skip(by: AudioPlayer.skipForwardSeconds)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.title)
                }
                .accessibilityLabel("30秒進む")
            }
            .disabled(player.isLoading)

            HStack {
                Menu {
                    Picker("再生速度", selection: $player.rate) {
                        ForEach(AudioPlayer.rates, id: \.self) { rate in
                            Text(rateLabel(rate)).tag(rate)
                        }
                    }
                } label: {
                    Label(rateLabel(player.rate), systemImage: "gauge.with.dots.needle.67percent")
                }

                Spacer()

                Button {
                    store.toggleFavorite(episode.id)
                } label: {
                    Image(systemName: state.favorite ? "heart.fill" : "heart")
                        .foregroundStyle(.pink)
                        .font(.title3)
                }
                .accessibilityLabel(state.favorite ? "お気に入り解除" : "お気に入り")

                Button {
                    store.setListened(episode.id, !state.listened)
                } label: {
                    Image(systemName: state.listened ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
                .padding(.leading, 16)
                .accessibilityLabel(state.listened ? "未聴にする" : "聴いたにする")
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var shownTime: Double {
        isScrubbing ? scrubTime : player.currentTime
    }

    private func rateLabel(_ rate: Float) -> String {
        "\(rate)x"  // 1.0x / 1.25x / 1.5x / 2.0x
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
