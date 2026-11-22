import AVFoundation
import Speech

/// Optional voice, off by default. Answers are spoken by the Mac's own synthesiser, and listening uses
/// on-device recognition only: when the on-device model is missing, Docket says so and never falls back
/// to Apple's servers.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        stop()
        synth.speak(AVSpeechUtterance(string: String(text.prefix(1200))))
    }

    func stop() { if synth.isSpeaking { synth.stopSpeaking(at: .immediate) } }
}

final class Listener: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var listening = false

    /// `onText` gets the running transcript and `onEnd` gets nil or a message to show, both on the main queue.
    func start(onText: @escaping @Sendable (String) -> Void, onEnd: @escaping @Sendable (String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                return DispatchQueue.main.async {
                    onEnd("Speech recognition is off for Docket. Turn it on in System Settings, Privacy & Security.")
                }
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    guard granted else {
                        return onEnd("Microphone access is off for Docket. Turn it on in System Settings, Privacy & Security.")
                    }
                    self.begin(onText: onText, onEnd: onEnd)
                }
            }
        }
    }

    private func begin(onText: @escaping @Sendable (String) -> Void, onEnd: @escaping @Sendable (String?) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else {
            return onEnd("On-device speech is not available for this language, so Docket will not listen. Audio never leaves the Mac.")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return onEnd("Could not start the microphone.")
        }
        self.request = request
        listening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            DispatchQueue.main.async {
                if let text { onText(text) }
                if done {
                    self?.stop()
                    self?.task = nil
                    onEnd(nil)
                }
            }
        }
    }

    /// Stops the microphone. The recogniser then sends its final text and `onEnd`.
    func stop() {
        guard listening else { return }
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
    }
}
