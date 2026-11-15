import XCTest
@testable import JotCore

final class SpaceHoldTests: XCTestCase {
    private func key(_ h: inout SpaceHold, space: Bool = true, down: Bool, repeating: Bool = false, modified: Bool = false, allowed: Bool = true) -> SpaceHold.Action {
        h.key(space: space, down: down, repeating: repeating, modified: modified, allowed: allowed)
    }
    func testQuickTapTypesExactlyOneSpace() {
        var h = SpaceHold()
        XCTAssertEqual(key(&h, down: true), .wait)
        XCTAssertEqual(key(&h, down: false), .typeSpace)
        XCTAssertEqual(h.phase, .idle)
        XCTAssertFalse(h.threshold(), "A timer firing after release must not start dictation")
    }
    func testHoldStartsDictationAndRepeatsNeverTypeSpaces() {
        var h = SpaceHold()
        XCTAssertEqual(key(&h, down: true), .wait)
        XCTAssertEqual(key(&h, down: true, repeating: true), .swallow)
        XCTAssertTrue(h.threshold())
        XCTAssertEqual(h.phase, .holding)
        XCTAssertEqual(key(&h, down: true, repeating: true), .swallow)
        XCTAssertEqual(key(&h, space: false, down: true), .pass)
        XCTAssertEqual(key(&h, down: false), .stop)
        XCTAssertEqual(h.phase, .idle)
    }
    func testModifiedSpaceAndOtherAppsPassThrough() {
        var h = SpaceHold()
        XCTAssertEqual(key(&h, down: true, modified: true), .pass)
        XCTAssertEqual(key(&h, down: false, modified: true), .pass)
        XCTAssertEqual(key(&h, down: true, allowed: false), .pass)
        XCTAssertEqual(key(&h, down: true, repeating: true, allowed: false), .pass)
        XCTAssertEqual(key(&h, down: false, allowed: false), .pass)
        XCTAssertEqual(key(&h, down: true, repeating: true), .pass, "A repeat (e.g. after releasing Shift) never starts a hold")
        XCTAssertEqual(key(&h, space: false, down: true), .pass)
        XCTAssertEqual(h.phase, .idle)
    }
    func testNextKeyDuringPendingFlushesTheSpaceFirst() {
        var h = SpaceHold()
        _ = key(&h, down: true)
        XCTAssertEqual(key(&h, space: false, down: false), .pass, "Previous letter's key-up does not flush")
        XCTAssertEqual(key(&h, space: false, down: true), .typeSpaceFirst)
        XCTAssertEqual(key(&h, down: false), .pass)
        XCTAssertFalse(h.threshold())
    }
    func testTapResetStopsOnlyARunningHold() {
        var h = SpaceHold()
        _ = key(&h, down: true)
        XCTAssertFalse(h.reset())
        _ = key(&h, down: true); _ = h.threshold()
        XCTAssertTrue(h.reset())
        XCTAssertEqual(h.phase, .idle)
        XCTAssertEqual(key(&h, down: false), .pass)
    }
    func testAllowlistMatchesBundleIDs() {
        for id in ["com.anthropic.claudefordesktop", "com.openai.chat", "com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2"] {
            XCTAssertTrue(SpaceHold.allows(id, in: SpaceHold.defaultApps), id)
        }
        XCTAssertTrue(SpaceHold.allows("com.apple.terminal", in: "  com.apple.Terminal \n\n"))
        XCTAssertTrue(SpaceHold.allows("b.app", in: "a.app, b.app"))
        XCTAssertFalse(SpaceHold.allows("com.apple.TextEdit", in: SpaceHold.defaultApps))
        XCTAssertFalse(SpaceHold.allows(nil, in: SpaceHold.defaultApps))
        XCTAssertFalse(SpaceHold.allows("", in: "\n\n"))
    }
    func testTranscribeArgumentParsing() throws {
        XCTAssertNil(TranscribeCommand.parse(["Jot"]))
        XCTAssertNil(TranscribeCommand.parse(["Jot", "--benchmark", "a.wav"]))
        XCTAssertEqual(try TranscribeCommand.parse(["Jot", "--transcribe", "/tmp/voice note.m4a"])?.get(), URL(fileURLWithPath: "/tmp/voice note.m4a"))
        XCTAssertEqual(try TranscribeCommand.parse(["Jot", "--transcribe", "clip.wav"])?.get().path, URL(fileURLWithPath: "clip.wav").path)
        XCTAssertThrowsError(try XCTUnwrap(TranscribeCommand.parse(["Jot", "--transcribe"])).get())
        XCTAssertThrowsError(try XCTUnwrap(TranscribeCommand.parse(["Jot", "--transcribe", ""])).get())
        XCTAssertThrowsError(try XCTUnwrap(TranscribeCommand.parse(["Jot", "--transcribe", "--ultra"])).get())
    }

    func testModifierTapNeedsALoneQuickPressWithNoKeyBetween() {
        var t = ModifierTap(); let t0 = Date()
        XCTAssertNil(t.flags(code: 54, down: true, alone: true, now: t0))
        XCTAssertEqual(t.flags(code: 54, down: false, alone: false, now: t0 + 0.2), 54)
        XCTAssertNil(t.flags(code: 54, down: true, alone: true, now: t0)); t.key()
        XCTAssertNil(t.flags(code: 54, down: false, alone: false, now: t0 + 0.2), "⌘C must not count as a tap")
        XCTAssertNil(t.flags(code: 54, down: true, alone: false, now: t0))
        XCTAssertNil(t.flags(code: 54, down: false, alone: false, now: t0 + 0.2), "with ⇧ held it's a combination")
        XCTAssertNil(t.flags(code: 54, down: true, alone: true, now: t0))
        XCTAssertNil(t.flags(code: 54, down: false, alone: false, now: t0 + 0.8), "a long hold isn't a tap")
    }
}
