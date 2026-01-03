import Foundation
import Speech
import AVFoundation
import Combine

final class DictationManager: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestAuthorization()
    }

    // MARK: - Authorization

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.isAuthorized = true
                    self?.requestMicrophoneAccess()

                case .denied, .restricted:
                    self?.isAuthorized = false
                    self?.errorMessage = "Speech recognition not authorized"

                case .notDetermined:
                    self?.isAuthorized = false

                @unknown default:
                    break
                }
            }
        }
    }

    private func requestMicrophoneAccess() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if !granted {
                    self?.isAuthorized = false
                    self?.errorMessage = "Microphone access required for dictation"
                }
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard isAuthorized else {
            requestAuthorization()
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition not available"
            return
        }

        // Cancel any ongoing task
        stopRecording()

        do {
            try startAudioSession()
            try startRecognition()

            isRecording = true
            errorMessage = nil

        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            stopRecording()
        }
    }

    private func startAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognition() throws {
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw DictationError.audioEngineUnavailable
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw DictationError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        // Use on-device recognition if available for privacy
        if #available(iOS 13, *) {
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                recognitionRequest.requiresOnDeviceRecognition = true
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString

                DispatchQueue.main.async {
                    self.transcribedText = text
                }

                // Check for terminal commands based on context
                self.processCommand(text)
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine = nil

        DispatchQueue.main.async {
            self.isRecording = false
        }

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Command Processing

    private func processCommand(_ text: String) {
        let lowercased = text.lowercased()

        // Detect common voice commands and translate them
        let commandMappings: [String: String] = [
            "control c": "\u{03}",
            "control d": "\u{04}",
            "control z": "\u{1A}",
            "escape": "\u{1B}",
            "enter": "\n",
            "new line": "\n",
            "tab": "\t",
            "up arrow": "\u{1B}[A",
            "down arrow": "\u{1B}[B",
            "left arrow": "\u{1B}[D",
            "right arrow": "\u{1B}[C",
        ]

        // Check for command phrases at the end of transcription
        for (phrase, replacement) in commandMappings {
            if lowercased.hasSuffix(phrase) {
                // Replace the phrase with the actual key sequence
                DispatchQueue.main.async {
                    let trimmedText = String(text.dropLast(phrase.count))
                    self.transcribedText = trimmedText + replacement
                }
                break
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        stopRecording()
    }
}

// MARK: - Errors

enum DictationError: LocalizedError {
    case audioEngineUnavailable
    case requestCreationFailed
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .audioEngineUnavailable:
            return "Audio engine is not available"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        case .notAuthorized:
            return "Speech recognition not authorized"
        }
    }
}

// MARK: - Voice Command Mode

extension DictationManager {
    struct VoiceCommand {
        let trigger: String
        let action: () -> Void
    }

    static let defaultVoiceCommands: [String: String] = [
        "clear screen": "clear",
        "list files": "ls -la",
        "go back": "cd ..",
        "show status": "git status",
        "show differences": "git diff",
        "make commit": "git commit -m \"",
        "exit": "exit",
        "help": "help",
    ]
}
