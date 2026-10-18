import AVFoundation
import MediaPlayer

/// 再生を担当する。音質の調整、ロック画面・イヤホンの操作、再生位置の保存もここで行う。
/// 音を加工するため、AVPlayer ではなく AVAudioEngine で
/// 「プレイヤー → 形式をそろえる → 速度 → イコライザー → 音量の差を縮める処理 → 出力」とつないで鳴らす
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
            timePitch.rate = rate
            updateNowPlaying()
        }
    }
    @Published var sound: SoundSettings {
        didSet {
            sound.save()
            applySound()
        }
    }
    /// 聴き終わったら次の回を再生する
    @Published var autoPlayNext: Bool {
        didSet { UserDefaults.standard.set(autoPlayNext, forKey: "autoPlayNext") }
    }

    /// 次の回（音声があるもの）を返す。アプリの起動時に一覧から設定する
    var nextEpisode: @MainActor (Episode) -> (Episode, AudioFile)? = { _ in nil }

    private let store: ListeningStore
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// ファイルごとに違う形式（モノラル / ステレオ、サンプリング周波数）を、ここで1つにそろえる
    private let converter = AVAudioMixerNode()
    private static let chainFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private let timePitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    private let dynamics = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))

    private var file: AVAudioFile?
    /// 今の区間をどこ（秒）から鳴らし始めたか
    private var segmentStart: Double = 0
    /// 区間を入れ直すたびに増やす（止めたときの完了通知を「聴き終わった」と取り違えないため）
    private var generation = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastSaved = Date.distantPast

    init(store: ListeningStore) {
        self.store = store
        let saved = UserDefaults.standard.float(forKey: "playbackRate")
        rate = Self.rates.contains(saved) ? saved : 1.0
        sound = SoundSettings.load()
        autoPlayNext = UserDefaults.standard.object(forKey: "autoPlayNext") as? Bool ?? true

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        setUpEngine()
        observeSession()
        setUpRemoteCommands()
    }

    // MARK: - 操作

    func play(_ episode: Episode, file audioFile: AudioFile) {
        if current?.id == episode.id {
            if !isPlaying { resume() }
            return
        }
        if isPlaying { pause() } else { saveProgress() }
        stopNode()
        file = nil
        current = episode
        currentTime = 0
        duration = store.state(episode.id).duration
        isLoading = true
        updateNowPlaying()

        Task {
            do {
                let url = try await AudioLibrary.prepare(audioFile)
                guard current?.id == episode.id else { return }

                let opened = try AVAudioFile(forReading: url)
                file = opened
                let rate = opened.processingFormat.sampleRate
                if rate > 0 { duration = Double(opened.length) / rate }

                // ファイルごとにチャンネル数などが違うので、つなぎ直す
                engine.disconnectNodeOutput(node)
                engine.connect(node, to: converter, format: opened.processingFormat)

                let state = store.state(episode.id)
                let start = state.listened ? 0 : max(0, state.position - Self.resumeRewindSeconds)
                schedule(from: start)
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
        guard file != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                errorMessage = "音を出せませんでした：\(error.localizedDescription)"
                return
            }
            // エンジンが止まると入れておいた区間も消えるので、今の位置から入れ直す
            schedule(from: currentTime)
        }
        node.play()
        setPlaying(true)
    }

    func pause() {
        updateCurrentTime()
        node.pause()
        setPlaying(false)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func seek(to seconds: Double) {
        guard file != nil else { return }
        let wasPlaying = isPlaying
        let upper = duration > 0 ? max(0, duration - 0.5) : seconds
        schedule(from: min(max(0, seconds), upper))
        if wasPlaying { node.play() }
        saveProgress()
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        updateCurrentTime()
        seek(to: currentTime + seconds)
    }

    /// 今の再生位置を保存する（数秒おき、一時停止、アプリが裏に回ったとき）
    func saveProgress() {
        guard let current, !isLoading, file != nil else { return }
        store.updatePosition(current.id, position: currentTime, duration: duration)
        lastSaved = Date()
    }

    // MARK: - 鳴らす仕組み

    private func setUpEngine() {
        for unit in [node, converter, timePitch, eq, dynamics] as [AVAudioNode] {
            engine.attach(unit)
        }
        let format = Self.chainFormat
        engine.connect(converter, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: dynamics, format: format)
        engine.connect(dynamics, to: engine.mainMixerNode, format: format)

        let bands = eq.bands
        bands[0].filterType = .highPass      // ゴーッという低いノイズを切る
        bands[0].frequency = 80
        bands[1].filterType = .lowShelf      // 低音
        bands[1].frequency = 200
        bands[2].filterType = .parametric    // 声
        bands[2].frequency = 2500
        bands[2].bandwidth = 1.5
        bands[3].filterType = .highShelf     // 高音
        bands[3].frequency = 6000
        bands[4].filterType = .lowPass       // 「サー」というノイズ
        bands[4].frequency = 7000
        for band in bands { band.bypass = false }

        // 小さい声を持ち上げ、大きい声を抑える
        let unit = dynamics.audioUnit
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -28, 0)
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 6, 0)
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.01, 0)
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.3, 0)

        timePitch.rate = rate
        applySound()
    }

    private func applySound() {
        let bands = eq.bands
        bands[1].gain = sound.bass
        bands[2].gain = sound.voice
        bands[3].gain = sound.treble
        bands[4].bypass = !sound.cutHiss
        eq.globalGain = sound.volume
        dynamics.bypass = !sound.evenLoudness
    }

    /// 指定した秒から最後までを鳴らす準備をする（鳴らし始めるのは呼び出し側）
    private func schedule(from seconds: Double) {
        guard let file else { return }
        stopNode()
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seconds * sampleRate)
        guard startFrame < file.length else { return }
        segmentStart = seconds
        currentTime = seconds
        generation += 1
        let token = generation
        node.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(file.length - startFrame),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == token else { return }
                    self.finished()
                }
            }
        }
    }

    private func stopNode() {
        generation += 1
        node.stop()
    }

    private func updateCurrentTime() {
        guard isPlaying,
              let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return }
        let seconds = segmentStart + Double(playerTime.sampleTime) / playerTime.sampleRate
        if seconds.isFinite, seconds >= 0 { currentTime = min(seconds, duration) }
    }

    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        timer?.invalidate()
        timer = nil
        if playing {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else {
            saveProgress()
        }
        updateNowPlaying()
    }

    private func tick() {
        guard !isLoading, let current else { return }
        updateCurrentTime()
        if duration > 0, currentTime / duration >= Self.listenedRatio, !store.state(current.id).listened {
            store.setListened(current.id, true)
        }
        if Date().timeIntervalSince(lastSaved) >= 5 {
            saveProgress()
        }
    }

    private func finished() {
        guard let episode = current else { return }
        isPlaying = false
        timer?.invalidate()
        timer = nil
        currentTime = 0
        store.setListened(episode.id, true)
        store.updatePosition(episode.id, position: 0, duration: duration)

        if autoPlayNext, let next = nextEpisode(episode) {
            play(next.0, file: next.1)
        } else {
            schedule(from: 0)
            updateNowPlaying()
        }
    }

    // MARK: - 中断やイヤホンの抜き差し

    private func observeSession() {
        let center = NotificationCenter.default

        // 電話などで中断され、終わったら再開する
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began {
                    if self.isPlaying { self.pause() }
                } else if shouldResume {
                    self.resume()
                }
            }
        })

        // イヤホンが抜けたら止める
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.pause()
            }
        })

        // 出力先が変わってエンジンが止まったら、止まった状態に合わせる
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, !self.engine.isRunning else { return }
                self.pause()
            }
        })
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
