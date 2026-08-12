import XCTest
@testable import EchoCue

final class ScriptEngineTests: XCTestCase {
    func testSplitsEnglishAndChineseSentences() {
        let input = "First sentence. Second sentence!\n第一句。第二句！"
        XCTAssertEqual(
            ScriptParser.segments(from: input),
            ["First sentence.", "Second sentence!", "第一句。", "第二句！"]
        )
    }

    func testDetectsChineseLocale() {
        XCTAssertEqual(ScriptParser.localeIdentifier(for: "这是一个中文提词器脚本。下一句。"), "zh-CN")
        XCTAssertEqual(ScriptParser.localeIdentifier(for: "This is an English teleprompter script."), "en-US")
    }

    func testMatcherToleratesExtraSpeech() {
        let score = FuzzyMatcher.score(
            target: "Echo turns your history into capability.",
            transcript: "Okay, so Echo turns your history into real capability for any agent."
        )
        XCTAssertGreaterThan(score, 0.70)
    }

    func testMatcherRejectsUnrelatedSpeech() {
        let score = FuzzyMatcher.score(
            target: "Echo turns your history into capability.",
            transcript: "The weather in San Francisco is unusually warm today."
        )
        XCTAssertLessThan(score, 0.35)
    }

    func testVoiceCommandOnlyFiresOnceForGrowingPartialTranscript() {
        var detector = VoiceAdvanceDetector()
        let phrases = ["you know", "you know what I mean", "for example"]

        XCTAssertFalse(detector.detectsNewCommand(in: "Echo stores your work", phrases: phrases))
        XCTAssertTrue(detector.detectsNewCommand(in: "Echo stores your work, you know", phrases: phrases))
        XCTAssertFalse(detector.detectsNewCommand(in: "Echo stores your work, you know what I mean", phrases: phrases))
        XCTAssertFalse(detector.detectsNewCommand(in: "Echo stores your work, you know what I mean, today", phrases: phrases))
        XCTAssertTrue(detector.detectsNewCommand(in: "Echo stores your work, you know what I mean, today, for example", phrases: phrases))
    }

    func testVoiceCommandResetsWithNewRecognitionSession() {
        var detector = VoiceAdvanceDetector()
        let phrases = ["next line"]

        XCTAssertTrue(detector.detectsNewCommand(in: "This is a much longer sentence and now I will say next line", phrases: phrases))
        XCTAssertTrue(detector.detectsNewCommand(in: "next line", phrases: phrases))
    }
}
