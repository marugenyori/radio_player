import SwiftUI

/// 音質の調整。動かすとすぐ再生中の音に反映される
struct SoundSettingsView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    slider("声をはっきり", value: $player.sound.voice, range: 0...12)
                    slider("低音", value: $player.sound.bass, range: -12...6)
                    slider("高音", value: $player.sound.treble, range: -12...12)
                    slider("音量", value: $player.sound.volume, range: 0...12)
                } footer: {
                    Text("こもって聞こえるときは「低音」を下げて「声をはっきり」を上げると聞きやすくなります。")
                }

                Section {
                    Toggle("声の大きさをそろえる", isOn: $player.sound.evenLoudness)
                    Toggle("「サー」というノイズを抑える", isOn: $player.sound.cutHiss)
                } footer: {
                    Text("「声の大きさをそろえる」は、小さい声を持ち上げて大きい声を抑えます。")
                }

                Section {
                    Button("おすすめの設定にする") { player.sound = .recommended }
                    Button("元の音に戻す") { player.sound = .flat }
                        .disabled(player.sound == .flat)
                }
            }
            .navigationTitle("音質")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func slider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%+.0f dB", value.wrappedValue))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}
