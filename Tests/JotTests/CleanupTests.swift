import XCTest
@testable import JotCore

final class CleanupTests: XCTestCase {
    func testCorrectionAllowedButLostUncertaintyRejected() {
        XCTAssertTrue(LocalCleanup.accepts(raw: "Can we go to the store Tuesday, I mean Wednesday.", cleaned: "Can we go to the store Wednesday?"))
        XCTAssertFalse(LocalCleanup.accepts(raw: "I think the total is around twelve hundred.", cleaned: "The total is about twelve hundred."))
        XCTAssertFalse(LocalCleanup.accepts(raw: "Don't send the file.", cleaned: "Send the file."))
        XCTAssertFalse(LocalCleanup.accepts(raw: "That was really, really good.", cleaned: "That was really good."))
        XCTAssertFalse(LocalCleanup.accepts(raw: "Send the file.", cleaned: "Send the file to Morgan."))
        XCTAssertTrue(LocalCleanup.hasQuotes("She said, 'I mean Wednesday,' and left."))
        XCTAssertFalse(LocalCleanup.hasQuotes("Don't change it."))
    }
    func testQuotesBypassModelAndOriginalMetadataRoundTrips() async throws {
        let raw = "Type the words \"um, like, you know\" exactly as written."
        let result = await LocalCleanup().clean(raw)
        XCTAssertEqual(result.text, raw)
        XCTAssertTrue(result.status.contains("quoted"))
        var entry = Dictation(text: "Wednesday", audioFile: nil, duration: 1, finishMS: 500, model: "Ultra", destination: "History", status: "Saved")
        entry.originalText = "Tuesday, I mean Wednesday"; entry.cleanupMS = 330; entry.cleanupStatus = "Cleaned locally"
        let decoded = try JSONDecoder().decode(Dictation.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded.originalText, entry.originalText)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        old.removeValue(forKey: "originalText"); old.removeValue(forKey: "cleanupMS"); old.removeValue(forKey: "cleanupStatus")
        XCTAssertNil(try JSONDecoder().decode(Dictation.self, from: JSONSerialization.data(withJSONObject: old)).originalText)
    }
    func testLocalModelCorrection() async throws {
        guard ProcessInfo.processInfo.environment["JOT_TEST_CLEANUP"] == "1" else { throw XCTSkip("Opt-in local Ollama integration") }
        let result = await LocalCleanup().clean("Can we go to the store Tuesday, I mean Wednesday.")
        XCTAssertEqual(result.text, "Can we go to the store Wednesday?")
        XCTAssertEqual(result.status, "Cleaned locally")
    }
}
