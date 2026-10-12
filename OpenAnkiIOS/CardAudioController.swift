import AVFoundation
import Observation
import OpenAnkiCore

@MainActor @Observable
final class CardAudioController: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private(set) var owner: String?
    private(set) var isPlaying = false
    private(set) var source: LocalizedMessage?
    private(set) var error: LocalizedMessage?
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var utterances = Set<ObjectIdentifier>()
    private var recordings: [URL] = []

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func readWord(card: Flashcard, mediaURL: URL?, owner: String) {
        begin(owner: owner)
        recordings = CardAudio.filenames(in: card.front + card.back).compactMap { name in
            guard let url = mediaURL?.appendingPathComponent(name), FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
        if playNextRecording() { return }
        if let pronunciation = card.pronunciation {
            speak([pronunciation.word], language: pronunciation.language)
        } else {
            error = "此卡片的录音文件缺失。"
        }
    }

    func readExamples(_ pronunciation: Pronunciation, owner: String) {
        begin(owner: owner)
        speak(pronunciation.examples, language: pronunciation.language)
    }

    func stop(owner requestedOwner: String? = nil) {
        guard requestedOwner == nil || requestedOwner == owner else { return }
        player?.stop()
        player = nil
        recordings = []
        utterances.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        releaseSession()
    }

    private func begin(owner: String) {
        stop()
        self.owner = owner
        source = nil
        error = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            self.error = "无法启动音频播放，请重试。"
        }
    }

    @discardableResult private func playNextRecording() -> Bool {
        while !recordings.isEmpty {
            let url = recordings.removeFirst()
            guard let candidate = try? AVAudioPlayer(contentsOf: url) else { continue }
            candidate.delegate = self
            player = candidate
            if candidate.play() {
                isPlaying = true
                source = "牌组录音"
                error = nil
                return true
            }
        }
        player = nil
        isPlaying = false
        return false
    }

    private func speak(_ texts: [String], language: String) {
        guard let voice = AVSpeechSynthesisVoice(language: language) else {
            error = "设备上没有可用的日语语音。请在 iOS 设置中下载日语语音后重试。"
            return
        }
        for text in texts where !text.isEmpty {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = 0.45
            utterance.postUtteranceDelay = 0.3
            utterances.insert(ObjectIdentifier(utterance))
            synthesizer.speak(utterance)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identifier else { return }
            if !flag { self.error = "无法播放此录音。" }
            if !self.playNextRecording() { self.releaseSession() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utterances.contains(identifier) else { return }
            self.isPlaying = true
            self.source = "日语语音"
            self.error = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utterances.remove(identifier) != nil else { return }
            if self.utterances.isEmpty {
                self.isPlaying = false
                self.releaseSession()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechSynthesizer(synthesizer, didFinish: utterance)
    }

    private func releaseSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
