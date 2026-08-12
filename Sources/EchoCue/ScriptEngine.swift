import Foundation

enum ScriptParser {
    private static let sentenceEnders: Set<Character> = [".", "?", "!", "。", "？", "！", ";", "；"]

    static func segments(from script: String) -> [String] {
        var result: [String] = []
        var buffer = ""

        func flush() {
            let cue = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cue.isEmpty {
                result.append(cue)
            }
            buffer = ""
        }

        for character in script {
            if character == "\n" || character == "\r" {
                flush()
                continue
            }

            buffer.append(character)
            if sentenceEnders.contains(character) {
                flush()
            }
        }
        flush()
        return result
    }

    static func localeIdentifier(for script: String) -> String {
        let scalars = script.unicodeScalars
        let cjkCount = scalars.filter { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }.count
        let letterCount = scalars.filter(CharacterSet.letters.contains).count
        return cjkCount > max(4, letterCount / 5) ? "zh-CN" : "en-US"
    }
}

enum FuzzyMatcher {
    static func tokens(in text: String) -> [String] {
        var result: [String] = []
        var latinBuffer = ""

        func flushLatin() {
            if !latinBuffer.isEmpty {
                result.append(latinBuffer)
                latinBuffer = ""
            }
        }

        for scalar in text.lowercased().unicodeScalars {
            let value = Int(scalar.value)
            if (0x4E00...0x9FFF).contains(value) {
                flushLatin()
                result.append(String(scalar))
            } else if CharacterSet.alphanumerics.contains(scalar) {
                latinBuffer.unicodeScalars.append(scalar)
            } else {
                flushLatin()
            }
        }
        flushLatin()
        return result
    }

    static func score(target: String, transcript: String) -> Double {
        let targetTokens = tokens(in: target)
        guard !targetTokens.isEmpty else { return 0 }

        let allSpoken = tokens(in: transcript)
        let windowSize = max(targetTokens.count * 3, 24)
        let spokenTokens = Array(allSpoken.suffix(windowSize))
        guard !spokenTokens.isEmpty else { return 0 }

        var previous = Array(repeating: 0, count: spokenTokens.count + 1)
        for targetToken in targetTokens {
            var current = Array(repeating: 0, count: spokenTokens.count + 1)
            for index in 1...spokenTokens.count {
                if targetToken == spokenTokens[index - 1] {
                    current[index] = previous[index - 1] + 1
                } else {
                    current[index] = max(previous[index], current[index - 1])
                }
            }
            previous = current
        }

        let orderedCoverage = Double(previous.last ?? 0) / Double(targetTokens.count)
        let targetSet = Set(targetTokens.filter { $0.count > 2 || targetTokens.count < 6 })
        let spokenSet = Set(spokenTokens)
        let keywordCoverage = targetSet.isEmpty
            ? orderedCoverage
            : Double(targetSet.intersection(spokenSet).count) / Double(targetSet.count)

        return orderedCoverage * 0.72 + keywordCoverage * 0.28
    }
}

struct VoiceAdvanceDetector {
    private var previousTokenCount = 0
    private var seenOccurrenceCounts: [String: Int] = [:]

    mutating func reset() {
        previousTokenCount = 0
        seenOccurrenceCounts.removeAll()
    }

    mutating func detectsNewCommand(in transcript: String, phrases: [String]) -> Bool {
        let transcriptTokens = FuzzyMatcher.tokens(in: transcript)
        let candidates = phrases
            .map { FuzzyMatcher.tokens(in: $0) }
            .filter { !$0.isEmpty }
        // If both "you know" and "you know what I mean" are configured,
        // treat the longer form as the same command rather than a second skip.
        let commandPhrases = candidates.filter { candidate in
            !candidates.contains { other in
                other.count < candidate.count && contains(other, inside: candidate)
            }
        }

        // Speech recognition periodically starts a fresh transcript. Its command
        // counters must start fresh too, but small partial-result corrections
        // should not cause the same phrase to fire twice.
        if transcriptTokens.count + 3 < previousTokenCount {
            seenOccurrenceCounts.removeAll()
        }
        previousTokenCount = transcriptTokens.count

        var foundNewCommand = false
        for phraseTokens in commandPhrases {
            let key = phraseTokens.joined(separator: " ")
            let count = occurrenceCount(of: phraseTokens, in: transcriptTokens)
            if count > (seenOccurrenceCounts[key] ?? 0) {
                foundNewCommand = true
            }
            seenOccurrenceCounts[key] = max(seenOccurrenceCounts[key] ?? 0, count)
        }
        return foundNewCommand
    }

    private func contains(_ needle: [String], inside haystack: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for index in 0...(haystack.count - needle.count) {
            if Array(haystack[index..<(index + needle.count)]) == needle {
                return true
            }
        }
        return false
    }

    private func occurrenceCount(of phrase: [String], in transcript: [String]) -> Int {
        guard phrase.count <= transcript.count else { return 0 }
        var count = 0
        var index = 0
        while index <= transcript.count - phrase.count {
            if Array(transcript[index..<(index + phrase.count)]) == phrase {
                count += 1
                index += phrase.count
            } else {
                index += 1
            }
        }
        return count
    }
}
