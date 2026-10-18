import Foundation

/// 音質の調整。再生中にそのまま反映される
struct SoundSettings: Codable, Equatable {
    /// 声の聞きやすさ（2.5kHz あたりを持ち上げる）0〜12 dB
    var voice: Float = 0
    /// 低音 -12〜6 dB（こもった音は下げると聞きやすい）
    var bass: Float = 0
    /// 高音 -12〜12 dB
    var treble: Float = 0
    /// 音量の底上げ 0〜12 dB
    var volume: Float = 0
    /// 小さい声と大きい声の差を縮める
    var evenLoudness = false
    /// 「サー」というノイズを抑える（7kHz より上を削る）
    var cutHiss = false

    static let flat = SoundSettings()
    static let recommended = SoundSettings(voice: 6, bass: -3, treble: 0, volume: 4, evenLoudness: true, cutHiss: false)

    private static let key = "soundSettings"

    static func load() -> SoundSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(SoundSettings.self, from: data) else { return .flat }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
