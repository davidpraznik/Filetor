import AVFoundation
import Observation
import Speech

/// Listens to the microphone and turns speech into text. It stops by itself after a pause.
/// Uses on-device recognition when the language supports it. macOS does not offer Slovenian.
@MainActor
@Observable
final class SpeechInput {
    private(set) var listening = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var onText: ((String) -> Void)?

    /// Starts listening. `onFailure` gets a short message when it cannot start.
    func start(onText: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        guard !listening else { return }
        Task {
            guard await Self.authorized() else {
                onFailure("Allow Microphone and Speech Recognition for Filetor in System Settings > Privacy & Security.")
                return
            }
            begin(onText: onText, onFailure: onFailure)
        }
    }

    /// Stops the microphone. The last words that were already heard are still delivered.
    func stop() {
        silence?.cancel()
        guard listening else { return }
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    private func begin(onText: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        guard !listening else { return }
        guard let recognizer = Self.recognizer(), recognizer.isAvailable else {
            onFailure("Speech recognition is not available for your language.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            onFailure("No microphone found.")
            return
        }
        Self.installTap(on: input, format: format, request: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            onFailure("Could not start the microphone.")
            return
        }

        self.request = request
        self.onText = onText
        listening = true
        armSilence(after: 6)
        let me = WeakRef(self)
        task = Self.startTask(recognizer, request) { text, finished in
            Task { @MainActor in me.value?.handle(text, finished: finished) }
        }
    }

    private func handle(_ text: String?, finished: Bool) {
        if let text, !text.isEmpty {
            onText?(text)
            if listening { armSilence(after: 1.4) }
        }
        if finished {
            stop()
            task = nil
            request = nil
            onText = nil
        }
    }

    /// Stops listening when nothing new was heard for a moment.
    private func armSilence(after seconds: Double) {
        silence?.cancel()
        silence = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            stop()
        }
    }

    // These run on audio and speech threads, so they must not belong to the main actor.
    private nonisolated static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest) {
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
        }
    }

    private nonisolated static func startTask(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                                              handler: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    private nonisolated static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// The first language from the system list that speech recognition supports, otherwise US English.
    private static func recognizer() -> SFSpeechRecognizer? {
        for id in Locale.preferredLanguages {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: id)) { return recognizer }
        }
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
}

private nonisolated final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    nonisolated init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}

private nonisolated final class WeakRef: @unchecked Sendable {
    weak var value: SpeechInput?
    nonisolated init(_ value: SpeechInput) { self.value = value }
}
