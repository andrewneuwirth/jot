import XCTest
@testable import JotCore

final class CleanupTests: XCTestCase {
    func testCorrectionAllowedButLostUncertaintyRejected() {
        XCTAssertTrue(LocalCleanup.accepts(raw: "Can we go to the store Tuesday, I mean Wednesday.", cleaned: "Can we go to the store Wednesday?"))
        XCTAssertFalse(LocalCleanup.accepts(raw: "I think the total is around twelve hundred.", cleaned: "The total is about twelve hundred."))
        XCTAssertFalse(LocalCleanup.accepts(raw: "Don't send the file.", cleaned: "Send the file."))
        XCTAssertFalse(LocalCleanup.accepts(raw: "That was really, really good.", cleaned: "That was really good."))
        XCTAssertFalse(LocalCleanup.accepts(raw: "Send the file.", cleaned: "Send the file to Morgan."))
        XCTAssertFalse(LocalCleanup.accepts(raw: "Don't send the file to Morgan yet.", cleaned: "Don't send the file to Morgan."))
        XCTAssertTrue(LocalCleanup.accepts(raw: "Um, so I was, I was thinking we could, uh, ship it Friday.", cleaned: "I was thinking we could ship it Friday."))
        XCTAssertTrue(LocalCleanup.hasQuotes("She said, 'I mean Wednesday,' and left."))
        XCTAssertFalse(LocalCleanup.hasQuotes("Don't change it."))
    }
    func testQuotesBypassModelAndOriginalMetadataRoundTrips() async throws {
        let raw = "Type the words \"um, like, you know\" exactly as written."
        let result = await LocalCleanup().clean(raw, route: .local(URL(fileURLWithPath: "/nonexistent")))
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
    static let samples = [
        "Can we move the team sync to Tuesday, I mean Wednesday, at four thirty?",
        "Um, so I was, I was thinking we could, uh, ship it Friday.",
        "The budget is twelve, sorry, fifteen thousand.",
        "Send the invoice to Sam, no wait, to Alex.",
        "I think it's around ten minutes, maybe less.",
        "Don't send the file to Morgan yet.",
        "Uh, I like the blue one, but, um, she likes the purple one.",
        "Type the words \"um, like, you know\" exactly as written.",
        "Make it fifteen, sorry, fifty dollars.",
        "Call Jordan, no wait, call Riley about the lease.",
        // Written after the prompt was frozen, as a holdout.
        "Put the meeting on the calendar for March, actually April third.",
        "We need, uh, we need about two hundred chairs for the, um, the event.",
        "Tell Maria the deadline is, I mean, it's not Friday anymore, it's next Monday.",
        "I'm not sure we can, like, afford it this year.",
        "Order the large, sorry, the medium pizza with, uh, mushrooms.",
        "It was really, really good, honestly.",
        "Can you remind me to call the dentist tomorrow at nine?",
        "The code is four seven two, no, four seven three one.",
    ]
    /// Opt-in: JOT_CLEANUP_MODEL=/path/to/model.gguf runs the samples through the real model and prints warm timings.
    func testLocalModelSamples() async throws {
        guard let path = ProcessInfo.processInfo.environment["JOT_CLEANUP_MODEL"] else { throw XCTSkip("Set JOT_CLEANUP_MODEL to a GGUF file") }
        let cleanup = LocalCleanup(), route = CleanupRoute.local(URL(fileURLWithPath: path))
        let load = Date(); let loaded = await cleanup.warm(URL(fileURLWithPath: path)); XCTAssertTrue(loaded)
        print("LOAD|\(Int(Date().timeIntervalSince(load) * 1000))ms")
        _ = await cleanup.clean("Warm up, um, the model.", route: route)
        for raw in Self.samples {
            let r = await cleanup.clean(raw, route: route); print("CLEAN|\(raw)|=>|\(r.text)|\(r.status)|\(Int(r.milliseconds))ms")
        }
        let r = await cleanup.clean("Can we go to the store Tuesday, I mean Wednesday.", route: route)
        XCTAssertTrue(r.text.contains("Wednesday") && !r.text.contains("Tuesday"), r.text)
    }
    func testCloudRequestCarriesOnlyTranscriptAndKeyHeader() throws {
        for p in CloudProvider.allCases {
            let r = p.request(instructions: "rules", transcript: "um hello", key: "k-123", model: p.defaultModel)
            XCTAssertEqual(r.url?.host, p.host)
            XCTAssertFalse(r.url!.absoluteString.contains("k-123"))
            let body = String(data: r.httpBody!, encoding: .utf8)!
            XCTAssertTrue(body.contains("<transcript>um hello<\\/transcript>") || body.contains("<transcript>um hello</transcript>"), body)
            XCTAssertFalse(body.contains("k-123"))
        }
        XCTAssertEqual(CloudProvider.openai.reply(Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Hello."}}]}"#.utf8)), "Hello.")
        XCTAssertEqual(CloudProvider.anthropic.reply(Data(#"{"stop_reason":"end_turn","content":[{"type":"text","text":"Hello."}]}"#.utf8)), "Hello.")
        XCTAssertNil(CloudProvider.anthropic.reply(Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)))
        XCTAssertEqual(CloudProvider.gemini.reply(Data(#"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"Hello."}]}}]}"#.utf8)), "Hello.")
        XCTAssertNil(CloudProvider.groq.reply(Data(#"{"error":{"message":"bad key"}}"#.utf8)))
    }
    func testModelHashCheck() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("jot-hash-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try CleanupModel.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
