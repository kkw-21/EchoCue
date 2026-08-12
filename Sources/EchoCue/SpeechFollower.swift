import AVFoundation
import Foundation
import Speech

final class SpeechFollower: NSObject, SFSpeechRecognizerDelegate {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var shouldRun = false
    private var transcriptHandler: ((String) -> Void)?
    private var stateHandler: ((String, Bool) -> Void)?

    func start(
        localeIdentifier: String,
        onTranscript: @escaping (String) -> Void,
        onState: @escaping (String, Bool) -> Void
    ) {
        transcriptHandler = onTranscript
        stateHandler = onState
        shouldRun = true

        requestPermissions { [weak self] granted, message in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.shouldRun else { return }
                guard granted else {
                    self.stateHandler?(message, false)
                    self.shouldRun = false
                    return
                }
                self.beginRecognition(localeIdentifier: localeIdentifier)
            }
        }
    }

    func stop() {
        shouldRun = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        stateHandler?("Paused", false)
    }

    private func requestPermissions(completion: @escaping (Bool, String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                completion(false, "Speech recognition permission is required")
                return
            }

            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                completion(true, "Ready")
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    completion(allowed, allowed ? "Ready" : "Microphone permission is required")
                }
            default:
                completion(false, "Microphone permission is required")
            }
        }
    }

    private func beginRecognition(localeIdentifier: String) {
        recognitionTask?.cancel()
        recognitionTask = nil

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        speechRecognizer = recognizer
        recognizer?.delegate = self

        guard let recognizer, recognizer.isAvailable else {
            stateHandler?("Speech recognition is unavailable", false)
            shouldRun = false
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            stateHandler?("No microphone input was found", false)
            shouldRun = false
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            stateHandler?("Listening", true)
        } catch {
            stateHandler?("Could not start microphone: \(error.localizedDescription)", false)
            shouldRun = false
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcriptHandler?(result.bestTranscription.formattedString)
            }

            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    guard self.shouldRun else { return }
                    self.audioEngine.stop()
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    self.beginRecognition(localeIdentifier: localeIdentifier)
                }
            }
        }
    }
}
