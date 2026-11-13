import XCTest
import AVFoundation
@testable import JotCore

final class JotTests: XCTestCase {
    func testVocabularyOnlyReplacesWholePhrasesAndEscapesTemplates() {
        XCTAssertEqual(TranscriptTools.applyVocabulary("tar's and stars cost ten bucks.", rules: "tar's = Tars\nten bucks = $10"), "Tars and stars cost $10.")
        XCTAssertEqual(TranscriptTools.applyVocabulary("Cartography", rules: "art = Art"), "Cartography")
    }
    func testWordErrorRateUsesEditDistanceAndIgnoresPunctuation() {
        XCTAssertEqual(TranscriptTools.wordErrorRate(reference: "Hello, world!", hypothesis: "hello world"), 0)
        XCTAssertEqual(TranscriptTools.wordErrorRate(reference: "keep the last word", hypothesis: "keep the last"), 0.25)
        XCTAssertEqual(TranscriptTools.wordErrorRate(reference: "one two", hypothesis: "one three two"), 0.5)
    }
    @MainActor func testLibrarySurvivesRelaunchAndKeepsHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(root: root)
        let id = library.addNote(body: "A thought worth keeping", title: "Test")
        library.vocabulary = "jot = Jot"; library.save()
        library.add(Dictation(text: "Final words", audioFile: "recovery.caf", duration: 2.1, finishMS: 210, model: "test", destination: "TextEdit", status: "Inserted"))
        let reopened = Library(root: root)
        XCTAssertEqual(reopened.notes.first?.id, id)
        XCTAssertEqual(reopened.notes.first?.body, "A thought worth keeping")
        XCTAssertEqual(reopened.history.first?.audioFile, "recovery.caf")
        XCTAssertEqual(reopened.vocabulary, "jot = Jot")
    }
    @MainActor func testUnreadableLibraryIsNeverOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("library.json")
        try Data("broken original".utf8).write(to: file)
        let library = Library(root: root)
        XCTAssertNotNil(library.error)
        library.addNote(body: "Do not overwrite")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "broken original")
    }
    @MainActor func testInterruptedAudioIsRecoveredOnlyOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordings = root.appendingPathComponent("Recordings")
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
        buffer.frameLength = 1600
        do {
            let file = try AVAudioFile(forWriting: recordings.appendingPathComponent("interrupted.caf"), settings: format.settings)
            try file.write(from: buffer)
        }
        let library = Library(root: root)
        library.recoverInterruptedRecordings()
        XCTAssertEqual(library.history.count, 1)
        XCTAssertEqual(library.history.first?.duration ?? 0, 0.1, accuracy: 0.001)
        let reopened = Library(root: root)
        reopened.recoverInterruptedRecordings()
        XCTAssertEqual(reopened.history.count, 1)
        XCTAssertEqual(reopened.history.first?.audioFile, "interrupted.caf")
    }

    @MainActor func testPlaceholderAndWebEditorsUseFinalPaste() {
        XCTAssertTrue(TextInsertion.requiresFinalPaste(bundleID: nil, value: "Do anything\n", placeholder: "Do anything"))
        XCTAssertTrue(TextInsertion.requiresFinalPaste(bundleID: "com.openai.codex", value: "", placeholder: nil))
        XCTAssertTrue(TextInsertion.requiresFinalPaste(bundleID: "com.google.Chrome", value: "Existing draft", placeholder: nil))
        XCTAssertFalse(TextInsertion.requiresFinalPaste(bundleID: "com.apple.TextEdit", value: "Existing draft", placeholder: nil))
    }

    func testOverlayOnlyGrowsWhenTextWraps() {
        XCTAssertEqual(OverlayLayout.height(""), OverlayLayout.height("one short line"))
        XCTAssertGreaterThan(OverlayLayout.height(String(repeating: "a long sentence ", count: 12)), OverlayLayout.height("short"))
        XCTAssertLessThanOrEqual(OverlayLayout.height(String(repeating: "word ", count: 1000)), 110)
    }

    func testAppleOnDevicePreviewFromFixture() async throws {
        guard ProcessInfo.processInfo.environment["JOT_INTEGRATION"] == "1" else { throw XCTSkip("Explicit local speech integration check") }
        let preview = ApplePreview()
        try await preview.prepare()
        try await preview.begin { _ in }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/jfk.wav")
        let file = try AVAudioFile(forReading: url)
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
            try file.read(into: buffer)
            await preview.append(buffer)
        }
        let result = try await preview.finish()
        XCTAssertTrue(result.lowercased().contains("country"), "Apple preview: \(result)")
        await preview.stop()
    }

    func testPreviewKeepsSeparatePhrasesAcrossPauses() {
        var t = PreviewTranscript()
        XCTAssertEqual(t.update(start: 0, end: 2, text: "First sentence.", isFinal: false), "First sentence.")
        XCTAssertEqual(t.update(start: 3, end: 4, text: "Second", isFinal: false), "First sentence. Second")
        XCTAssertEqual(t.update(start: 3, end: 5, text: "Second sentence.", isFinal: true), "First sentence. Second sentence.")
        XCTAssertEqual(t.update(start: 6, end: 7, text: "", isFinal: false), "First sentence. Second sentence.")
    }
    func testPreviewRevisionsAndRepeatedFinalDoNotDuplicate() {
        var t = PreviewTranscript()
        _ = t.update(start: 0, end: 1, text: "I thing", isFinal: false)
        XCTAssertEqual(t.update(start: 0, end: 2, text: "I think so.", isFinal: true), "I think so.")
        XCTAssertEqual(t.update(start: 0, end: 2, text: "I think so.", isFinal: true), "I think so.")
        XCTAssertEqual(t.update(start: 0, end: 2, text: "", isFinal: false), "I think so.")
        XCTAssertEqual(t.update(start: 3, end: 5, text: "I think so.", isFinal: true), "I think so. I think so.")
    }
    func testPreviewRevisionWithShiftedRangeReplacesInsteadOfDuplicating() {
        // From a real call: "Okay, good. Okay, good." / "speakeak … speak"
        var t = PreviewTranscript()
        _ = t.update(start: 5.00, end: 6.10, text: "Okay, good.", isFinal: false)
        XCTAssertEqual(t.update(start: 5.04, end: 6.12, text: "Okay, good.", isFinal: true), "Okay, good.")
        _ = t.update(start: 7.0, end: 9.0, text: "No, I actually speakeak.", isFinal: false)
        XCTAssertEqual(t.update(start: 7.02, end: 8.9, text: "No, I actually speak.", isFinal: true), "Okay, good. No, I actually speak.")
        // A later final for the same audio does not add a third copy.
        XCTAssertEqual(t.update(start: 7.05, end: 8.95, text: "No, I actually speak.", isFinal: true), "Okay, good. No, I actually speak.")
        // Saying the same words again later is kept.
        XCTAssertEqual(t.update(start: 12, end: 13, text: "Okay, good.", isFinal: true), "Okay, good. No, I actually speak. Okay, good.")
    }
    func testPreviewRetainsRetractedProvisionalTextUntilRecordingEnds() {
        var t = PreviewTranscript()
        _ = t.update(start: 0, end: 2, text: "Keep this.", isFinal: true)
        _ = t.update(start: 3, end: 4, text: "Noise", isFinal: false)
        XCTAssertEqual(t.update(start: 3, end: 4, text: "", isFinal: false), "Keep this. Noise")
    }

    func testPreviewRetainsSentenceAfterPauseRetractionAndOverlap() {
        var t = PreviewTranscript()
        let first = "so this is me testing"
        XCTAssertEqual(t.update(start: 0, end: 3, text: first, isFinal: false), first)
        XCTAssertEqual(t.update(start: 0, end: 3, text: "", isFinal: false), first)
        XCTAssertEqual(t.update(start: 0, end: 3, text: "so this", isFinal: false), first)
        XCTAssertEqual(t.update(start: 2.9, end: 5, text: "and these are my next words", isFinal: false), first + " and these are my next words")
        XCTAssertEqual(t.update(start: 2.9, end: 5, text: "", isFinal: true), first + " and these are my next words")
        XCTAssertEqual(PreviewTranscript().text, "")
    }

}
