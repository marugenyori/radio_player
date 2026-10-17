import AVFoundation
import MediaPlayer

/// 再生を担当する。ロック画面・イヤホンの操作と、再生位置の保存もここで行う
@MainActor
final class AudioPlayer: ObservableObject {
    static let rates: [Float] = [1.0, 1.25, 1.5, 2.0]
    static let skipBackSeconds: Double = 15
    static let skipForwardSeconds: Double = 30
    /// 続きから再生するとき、少し前に戻す秒数
    static let resumeRewindSeconds: Double = 3
    /// ここまで再生したら「聴いた」にする
    static let listenedRatio: Double = 0.97

    @Published private(set) var current: Episode?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var errorMessage: String?
    @Published var rate: Float {
        didSet {
            UserDefaults.standard.set(rate, forKey: "playbackRate")
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
            updateNowPlaying()
        }
    }

    private let player = AVPlayer()
    private let store: ListeningStore
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var lastSaved = Date.distantPast

    init(store: ListeningStore) {
        self.store = store
        let saved = UserDefaults.standard.float(forKey: "playbackRate")
        rate = Self.rates.contains(saved) ? saved : 1.0
        player.defaultRate = rate

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        observePlayer()
        setUpRemoteCommands()
    }

    // MARK: - 操作

    func play(_ episode: Episode, file: AudioFile) {
        if current?.id == episode.id {
            if !isPlaying { resume() }
            return
        }
        saveProgress()
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = episode
        currentTime = 0
        duration = store.state(episode.id).duration
        isLoading = true
        updateNowPlaying()

        Task {
            do {
                let url = try await AudioLibrary.prepare(file)
                guard current?.id == episode.id else { return }

                let item = AVPlayerItem(url: url)
                let seconds = try await item.asset.load(.duration).seconds
                guard current?.id == episode.id else { return }
                if seconds.isFinite, seconds > 0 { duration = seconds }

                player.replaceCurrentItem(with: item)
                observeEnd(of: item)

                let state = store.state(episode.id)
                let start = state.listened ? 0 : max(0, state.position - Self.resumeRewindSeconds)
                if start > 0 {
                    _ = await player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
                }
                currentTime = start
                isLoading = false
                resume()
            } catch {
                guard current?.id == episode.id else { return }
                isLoading = false
                current = nil
                updateNowPlaying()
                errorMessage = "\(episode.show.name) \(episode.numberLabel)：\(error.localizedDescription)"
            }
        }
    }

    func resume() {
        guard player.currentItem != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: rate)
    }

    func pause() {
        player.pause()
        saveProgress()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func seek(to seconds: Double) {
        guard player.currentItem != nil else { return }
        let upper = duration > 0 ? duration : seconds
        let target = min(max(0, seconds), upper)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.updateNowPlaying()
                self?.saveProgress()
            }
        }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// 今の再生位置を保存する（数秒おき、一時停止、アプリが裏に回ったとき）
    func saveProgress() {
        guard let current, !isLoading, player.currentItem != nil else { return }
        store.updatePosition(current.id, position: currentTime, duration: duration)
        lastSaved = Date()
    }

    // MARK: - 監視

    private func observePlayer() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.tick(time.seconds)
            }
        }

        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isPlaying != playing else { return }
                    self.isPlaying = playing
                    if !playing { self.saveProgress() }
                    self.updateNowPlaying()
                }
            }
        }

        // 電話などで中断され、終わったら再開する
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .ended,
                  let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) else { return }
            MainActor.assumeIsolated {
                self?.resume()
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finished()
            }
        }
    }

    private func tick(_ seconds: Double) {
        guard !isLoading, seconds.isFinite, let current else { return }
        currentTime = seconds
        if duration > 0, seconds / duration >= Self.listenedRatio, !store.state(current.id).listened {
            store.setListened(current.id, true)
        }
        if isPlaying, Date().timeIntervalSince(lastSaved) >= 5 {
            saveProgress()
        }
    }

    private func finished() {
        guard let current else { return }
        store.setListened(current.id, true)
        store.updatePosition(current.id, position: 0, duration: duration)
        player.seek(to: .zero)
        currentTime = 0
        updateNowPlaying()
    }

    // MARK: - ロック画面とイヤホン

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBackSeconds)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -Self.skipBackSeconds) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForwardSeconds)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: Self.skipForwardSeconds) }
            return .success
        }

        // イヤホンのダブルクリック・トリプルクリックは「次の曲・前の曲」として届くので、送り・戻しにする
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: Self.skipForwardSeconds) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -Self.skipBackSeconds) }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let current else {
            center.nowPlayingInfo = nil
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "\(current.numberLabel) \(current.displayTitle)",
            MPMediaItemPropertyArtist: current.show.fullName,
            MPMediaItemPropertyAlbumTitle: current.show.name,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
        ]
    }
}
