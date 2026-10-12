// Queue semantics adapted from ankitects/anki 26.09.3, qt/aqt/sound.py.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import AVFoundation
import AudioToolbox
import Observation
import KiokitCore

@MainActor @Observable
final class CardAudioController {
    private(set) var owner: String?
    private(set) var isPlaying = false
    private(set) var source: LocalizedMessage?
    private(set) var error: LocalizedMessage?
    private(set) var videoPlayer: AVPlayer?
    private var applicationActive = false
    private var sessionActive = false
    private var generation = UUID()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let gain = AVAudioUnitEQ(numberOfBands: 0)
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let synthesizer = AVSpeechSynthesizer()
    private var currentFile: AVAudioFile?
    private var temporaryAudio: URL?
    private var writer: SpeechAudioFile?
    private var items: [AnkiAudioTag] = []
    private var mediaURL: URL?
    private var attemptedFile: String?
    private var mediaPlayer: AVPlayer?
    private var mediaTask: Task<Void, Never>?
    private var mediaPlaybackIdentity: UUID?
    private var mediaNotifications: [NSObjectProtocol] = []
    private var mediaStatus: NSKeyValueObservation?
    private var mediaTimeObserver: Any?
    private var videoGainDB: Float?
    private var videoProcessingError: OSStatus?

    init() {
        gain.globalGain = 6
        gain.bypass = false
        limiter.bypass = false
        player.volume = 1
        engine.attach(player)
        engine.attach(gain)
        engine.attach(limiter)
        synthesizer.usesApplicationAudioSession = true
    }

    func setApplicationActive(_ active: Bool) {
        applicationActive = active
        if active {
            do { try configureSession(duck: false) }
            catch { self.error = "无法启动音频播放，请重试。" }
        } else {
            stop()
        }
        diagnostics()
    }

    func play(_ tags: [AnkiAudioTag], mediaURL: URL, owner: String) {
        begin(owner: owner)
        self.mediaURL = mediaURL
        items = tags
        playNext()
    }

    func stop(owner requestedOwner: String? = nil) {
        guard requestedOwner == nil || requestedOwner == owner else { return }
        generation = UUID()
        mediaTask?.cancel()
        mediaTask = nil
        releaseMediaPlayer()
        player.stop()
        engine.stop()
        currentFile = nil
        writer?.cancel()
        writer = nil
        synthesizer.stopSpeaking(at: .immediate)
        removeTemporaryAudio()
        items = []
        isPlaying = false
        settleSession()
    }

    private func begin(owner: String) {
        stop()
        self.owner = owner
        source = nil
        error = nil
    }

    private func configureSession(duck: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: duck ? [.duckOthers] : [.mixWithOthers])
        try session.setActive(true)
        sessionActive = true
    }

    private func settleSession() {
        if applicationActive {
            try? configureSession(duck: false)
        } else {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            sessionActive = false
        }
        diagnostics()
    }

    /// Follows the upstream AV player's ordered tag queue; iOS handles the
    /// recording/TTS devices and gain, without inferring speech from note fields.
    private func playNext() {
        while !items.isEmpty {
            let tag = items.removeFirst()
            if let filename = tag.filename, let mediaURL {
                attemptedFile = mediaURL.appendingPathComponent(filename).path
                // Like sound.py::MpvManager(SoundOrVideoPlayer), accept every
                // SoundOrVideoTag. The platform decoder detects actual tracks;
                // an audio extension such as .3gp can also contain video.
                playMedia(mediaURL.appendingPathComponent(filename))
                return
            } else if tag.text != nil {
                renderSpeech(tag)
                return
            }
        }
        isPlaying = false
        player.stop()
        engine.stop()
        settleSession()
    }

    private func playFile(_ url: URL, source: LocalizedMessage) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw CocoaError(.fileReadCorruptFile) }
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(gain)
        engine.disconnectNodeOutput(limiter)
        engine.connect(player, to: gain, format: file.processingFormat)
        engine.connect(gain, to: limiter, format: file.processingFormat)
        engine.connect(limiter, to: engine.mainMixerNode, format: file.processingFormat)
        try configureSession(duck: true)
        try engine.start()
        currentFile = file
        let token = generation
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.currentFile = nil
                self.removeTemporaryAudio()
                self.playNext()
            }
        }
        player.play()
        isPlaying = true
        self.source = source
        error = nil
        diagnostics()
    }

    private func playMedia(_ url: URL) {
        player.stop()
        engine.stop()
        currentFile = nil
        let token = generation
        let identity = UUID()
        mediaPlaybackIdentity = identity
        isPlaying = true
        source = "牌组录音"
        error = nil
        videoGainDB = nil
        videoProcessingError = nil
        mediaTask = Task { [weak self] in
            guard let self else { return }
            do {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable) else { throw CocoaError(.fileReadCorruptFile) }
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                guard self.generation == token, self.mediaPlaybackIdentity == identity, !Task.isCancelled else { return }
                let item = AVPlayerItem(asset: asset)
                let mix = AVMutableAudioMix()
                mix.inputParameters = try audioTracks.map { track in
                    try MediaAudioGain.parameters(for: track) { [weak self] status, gain in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == token, self.mediaPlaybackIdentity == identity else { return }
                            self.videoGainDB = gain
                            self.videoProcessingError = status
                            if status != noErr { self.error = "无法播放此卡片的媒体文件。" }
                            self.diagnostics()
                        }
                    }
                }
                item.audioMix = mix
                let playback = AVPlayer(playerItem: item)
                playback.volume = 1
                self.mediaPlayer = playback
                if !videoTracks.isEmpty { self.videoPlayer = playback }
                self.mediaNotifications = [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification].map { name in
                    NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] notification in
                        let failed = notification.name == AVPlayerItem.failedToPlayToEndTimeNotification
                        Task { @MainActor [weak self] in self?.finishMedia(token: token, identity: identity, failed: failed) }
                    }
                }
                self.mediaStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    if item.status == .failed {
                        Task { @MainActor [weak self] in self?.finishMedia(token: token, identity: identity, failed: true) }
                    }
                }
                #if DEBUG
                self.mediaTimeObserver = playback.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, self.mediaPlaybackIdentity == identity else { return }
                        self.diagnostics()
                    }
                }
                #endif
                try self.configureSession(duck: true)
                playback.play()
                self.mediaTask = nil
                self.diagnostics()
            } catch {
                guard self.generation == token, self.mediaPlaybackIdentity == identity, !Task.isCancelled else { return }
                self.mediaTask = nil
                self.finishMedia(token: token, identity: identity, failed: true)
            }
        }
    }

    private func finishMedia(token: UUID, identity: UUID, failed: Bool) {
        guard generation == token, mediaPlaybackIdentity == identity else { return }
        releaseMediaPlayer()
        if failed { error = "无法播放此卡片的媒体文件。" }
        // Like aqt/sound.py::_on_play_finished, decoding errors finish this
        // player and advance to the next queued tag. Manual stop clears it.
        playNext()
    }

    private func releaseMediaPlayer() {
        mediaPlaybackIdentity = nil
        mediaNotifications.forEach(NotificationCenter.default.removeObserver)
        mediaNotifications = []
        mediaStatus = nil
        if let mediaPlayer, let mediaTimeObserver { mediaPlayer.removeTimeObserver(mediaTimeObserver) }
        mediaTimeObserver = nil
        mediaPlayer?.pause()
        mediaPlayer?.replaceCurrentItem(with: nil)
        videoPlayer = nil
        mediaPlayer = nil
    }

    private func renderSpeech(_ tag: AnkiAudioTag) {
        guard let text = tag.text, tag.language != nil else { playNext(); return }
        // Voice matching follows aqt/tts.py::voice_for_tag: preferences in order,
        // then the first installed voice matching the requested language.
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let available = voices.map { AnkiTTSVoice(identifier: $0.identifier, name: "Apple_" + $0.name.replacingOccurrences(of: " ", with: "_"), language: $0.language.replacingOccurrences(of: "-", with: "_")) }
        guard let match = AnkiAVFrontend.voice(for: tag, available: available), let voice = voices.first(where: { $0.identifier == match.voice.identifier }) else {
            error = "设备上没有可用的指定语言语音，请下载语音后重试。"
            isPlaying = false
            settleSession()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(tag.speed)
        utterance.volume = 1
        let output = SpeechAudioFile()
        writer = output
        let token = generation
        isPlaying = true
        synthesizer.write(utterance) { [weak self] buffer in
            guard let result = output.consume(buffer) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { output.cancel(); return }
                self.writer = nil
                switch result {
                case .success(let url):
                    self.temporaryAudio = url
                    do { try self.playFile(url, source: "设备语音") }
                    catch { self.failSpeech() }
                case .failure: self.failSpeech()
                }
            }
        }
    }

    private func failSpeech() {
        removeTemporaryAudio()
        isPlaying = false
        error = "无法合成或播放语音，请重试。"
        // Upstream playback failures invoke on_done and continue the queue;
        // only an explicit stop clears the remaining tags.
        playNext()
    }

    private func removeTemporaryAudio() {
        if let temporaryAudio { try? FileManager.default.removeItem(at: temporaryAudio) }
        temporaryAudio = nil
    }

    private func diagnostics() {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["OPENANKI_AUDIO_DIAGNOSTICS_FILE"] {
            let data: [String: Any] = ["foreground": applicationActive, "sessionActive": sessionActive,
                "category": AVAudioSession.sharedInstance().category.rawValue,
                "gainDB": gain.globalGain, "peakLimiter": !limiter.bypass, "playing": isPlaying]
            var report = data
            report["owner"] = owner ?? ""
            report["source"] = source?.key ?? ""
            report["error"] = error?.key ?? ""
            report["attemptedFile"] = attemptedFile ?? ""
            report["playerKind"] = mediaPlayer == nil ? "synthesizedAudio" : "soundOrVideo"
            report["videoVisible"] = videoPlayer != nil
            report["videoSeconds"] = mediaPlayer?.currentTime().seconds ?? 0
            report["videoGainDB"] = videoGainDB
            report["videoProcessingError"] = videoProcessingError
            report["queuedTags"] = items.count
            if let json = try? JSONSerialization.data(withJSONObject: report) {
                try? json.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
        #endif
    }
}

/// Serializes synthesis callbacks into a temporary file, including cancellation.
private final class SpeechAudioFile: @unchecked Sendable {
    private let lock = NSLock()
    private let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
    private var file: AVAudioFile?
    private var finished = false

    func consume(_ buffer: AVAudioBuffer) -> Result<URL, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        do {
            guard let pcm = buffer as? AVAudioPCMBuffer else { throw CocoaError(.fileReadCorruptFile) }
            if pcm.frameLength <= 1 {
                guard file != nil else { throw CocoaError(.fileReadCorruptFile) }
                file = nil
                finished = true
                return .success(url)
            }
            if file == nil { file = try AVAudioFile(forWriting: url, settings: pcm.format.settings) }
            try file?.write(from: pcm)
            return nil
        } catch {
            file = nil
            finished = true
            try? FileManager.default.removeItem(at: url)
            return .failure(error)
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        finished = true
        file = nil
        try? FileManager.default.removeItem(at: url)
    }
}
