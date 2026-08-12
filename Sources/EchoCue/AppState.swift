import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var scriptText: String
    @Published private(set) var cues: [String] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var transcript = ""
    @Published private(set) var matchProgress = 0.0
    @Published private(set) var isListening = false
    @Published private(set) var statusText = "Paused"
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }
    @Published var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: Keys.backgroundOpacity) }
    }
    @Published var captureProtectionEnabled: Bool {
        didSet { defaults.set(captureProtectionEnabled, forKey: Keys.captureProtection) }
    }
    @Published var voiceAdvancePhrases: String {
        didSet { defaults.set(voiceAdvancePhrases, forKey: Keys.voiceAdvancePhrases) }
    }
    @Published var rightArrowAdvanceEnabled: Bool {
        didSet { defaults.set(rightArrowAdvanceEnabled, forKey: Keys.rightArrowAdvance) }
    }

    private let speechFollower = SpeechFollower()
    private let defaults = UserDefaults.standard
    private var lastAdvanceTime = Date.distantPast
    private var voiceAdvanceDetector = VoiceAdvanceDetector()

    private enum Keys {
        static let script = "script"
        static let fontSize = "fontSize"
        static let backgroundOpacity = "backgroundOpacity"
        static let captureProtection = "captureProtection"
        static let voiceAdvancePhrases = "voiceAdvancePhrases"
        static let rightArrowAdvance = "rightArrowAdvance"
    }

    private init() {
        scriptText = defaults.string(forKey: Keys.script) ?? DefaultScript.text
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 31
        backgroundOpacity = defaults.object(forKey: Keys.backgroundOpacity) as? Double ?? 0.82
        captureProtectionEnabled = defaults.object(forKey: Keys.captureProtection) as? Bool ?? true
        voiceAdvancePhrases = defaults.string(forKey: Keys.voiceAdvancePhrases)
            ?? "you know, you know what I mean, for example, next line, 下一句, 换行"
        rightArrowAdvanceEnabled = defaults.object(forKey: Keys.rightArrowAdvance) as? Bool ?? true
        cues = ScriptParser.segments(from: scriptText)
    }

    var previousCue: String? {
        guard currentIndex > 0, currentIndex <= cues.count else { return nil }
        return cues[currentIndex - 1]
    }

    var currentCue: String? {
        guard cues.indices.contains(currentIndex) else { return nil }
        return cues[currentIndex]
    }

    var nextCue: String? {
        let index = currentIndex + 1
        guard cues.indices.contains(index) else { return nil }
        return cues[index]
    }

    func applyScript(resetPosition: Bool = true) {
        let parsed = ScriptParser.segments(from: scriptText)
        cues = parsed
        defaults.set(scriptText, forKey: Keys.script)
        if resetPosition || !cues.indices.contains(currentIndex) {
            currentIndex = 0
        }
        transcript = ""
        matchProgress = 0
        voiceAdvanceDetector.reset()
        statusText = parsed.isEmpty ? "Paste a script to begin" : "Ready: \(parsed.count) cues"
    }

    func importTextFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            scriptText = contents
            applyScript()
        }
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        guard !cues.isEmpty else {
            statusText = "Paste a script first"
            return
        }

        transcript = ""
        voiceAdvanceDetector.reset()
        let locale = ScriptParser.localeIdentifier(for: scriptText)
        statusText = "Requesting microphone…"
        speechFollower.start(
            localeIdentifier: locale,
            onTranscript: { [weak self] text in
                DispatchQueue.main.async {
                    self?.consume(transcript: text)
                }
            },
            onState: { [weak self] status, listening in
                DispatchQueue.main.async {
                    self?.statusText = status
                    self?.isListening = listening
                }
            }
        )
    }

    func stopListening() {
        speechFollower.stop()
        isListening = false
        statusText = "Paused"
    }

    func advance() {
        guard currentIndex + 1 < cues.count else {
            matchProgress = 1
            statusText = "Finished"
            return
        }
        currentIndex += 1
        matchProgress = 0
        lastAdvanceTime = Date()
    }

    func advanceByKeyboard() {
        advance()
        statusText = "→ key → Listening"
    }

    func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        matchProgress = 0
        transcript = ""
        voiceAdvanceDetector.reset()
    }

    func restart() {
        currentIndex = 0
        transcript = ""
        matchProgress = 0
        voiceAdvanceDetector.reset()
        statusText = isListening ? "Listening" : "Ready"
    }

    private func consume(transcript newTranscript: String) {
        transcript = newTranscript

        let phrases = voiceAdvancePhrases
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if voiceAdvanceDetector.detectsNewCommand(in: newTranscript, phrases: phrases) {
            matchProgress = 1
            advance()
            statusText = "Voice skip → Listening"
            return
        }

        guard let cue = currentCue else { return }
        let score = FuzzyMatcher.score(target: cue, transcript: newTranscript)
        matchProgress = min(max(score, 0), 1)

        let tokenCount = FuzzyMatcher.tokens(in: cue).count
        let threshold = tokenCount <= 4 ? 0.82 : 0.70
        let enoughTimePassed = Date().timeIntervalSince(lastAdvanceTime) > 0.55
        if score >= threshold && enoughTimePassed {
            advance()
        }
    }
}
