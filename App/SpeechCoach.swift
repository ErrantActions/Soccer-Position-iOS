import AVFoundation
import Observation
import OSLog

@MainActor @Observable
final class SpeechCoach: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var speaking = false
    private(set) var error: String?
    private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var active: ObjectIdentifier?
    private let logger = Logger(subsystem: "com.errantactions.soccerposition", category: "Speech")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            active = ObjectIdentifier(utterance)
            speaking = true
            error = nil
            synthesizer.speak(utterance)
        } catch { report(error) }
    }

    func stop() {
        let wasSpeaking = speaking
        active = nil
        synthesizer.stopSpeaking(at: .immediate)
        speaking = false
        if wasSpeaking { deactivate() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }

    private func finished(_ id: ObjectIdentifier) {
        guard active == id else { return }
        active = nil
        speaking = false
        deactivate()
    }
    private func deactivate() {
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { report(error) }
    }
    private func report(_ problem: Error) {
        logger.error("Spoken coaching failed: \(String(describing: problem), privacy: .private)")
        error = "Spoken coaching could not use the audio session. Try again."
        speaking = false
    }
}
