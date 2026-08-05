import AVFoundation
import Observation
import Speech

enum ChatFoodDictationPhase: Equatable {
    case idle
    case listening
    case denied
}

@MainActor
@Observable
final class ChatFoodDictationController {
    private(set) var phase: ChatFoodDictationPhase = .idle
    private(set) var partialTranscript = ""
    private(set) var errorMessage: String?

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    var isListening: Bool {
        phase == .listening
    }

    func toggleListening(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        switch phase {
        case .listening:
            stopListening(onFinal: onFinal)
        case .idle, .denied:
            Task {
                await startListening(onPartial: onPartial, onFinal: onFinal)
            }
        }
    }

    func cancel() {
        tearDownRecognition()
        partialTranscript = ""
        if phase == .listening {
            phase = .idle
        }
    }

    private func startListening(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) async {
        errorMessage = nil
        partialTranscript = ""

        guard let speechRecognizer else {
            phase = .denied
            errorMessage = "Speech recognition is not available for this language."
            return
        }

        guard speechRecognizer.isAvailable else {
            phase = .denied
            errorMessage = "Speech recognition is unavailable right now."
            return
        }

        let speechAuthorized = await requestSpeechAuthorization()
        guard speechAuthorized else {
            phase = .denied
            errorMessage = "Allow speech recognition in Settings to dictate meals."
            return
        }

        let micAuthorized = await requestMicrophoneAuthorization()
        guard micAuthorized else {
            phase = .denied
            errorMessage = "Allow microphone access in Settings to dictate meals."
            return
        }

        do {
            try beginRecognition(with: speechRecognizer, onPartial: onPartial, onFinal: onFinal)
            phase = .listening
        } catch {
            tearDownRecognition()
            phase = .idle
            errorMessage = error.localizedDescription
        }
    }

    private func stopListening(onFinal: @escaping (String) -> Void) {
        let transcript = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        tearDownRecognition()
        phase = .idle
        partialTranscript = ""
        guard !transcript.isEmpty else { return }
        onFinal(transcript)
    }

    private func beginRecognition(
        with speechRecognizer: SFSpeechRecognizer,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) throws {
        tearDownRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    let transcript = result.bestTranscription.formattedString
                    self.partialTranscript = transcript
                    onPartial(transcript)
                }

                if error != nil, self.phase == .listening {
                    self.tearDownRecognition()
                    self.phase = .idle
                    self.partialTranscript = ""
                    self.errorMessage = "Could not transcribe that. Try again."
                }
            }
        }
    }

    private func tearDownRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
