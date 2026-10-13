import XCTest
@testable import JotCore
final class SmartPasteTests: XCTestCase {
    @MainActor func testFinishDestinationRequiresEditableNonSecureText() {
        XCTAssertTrue(TextInsertion.canRetarget(role: "AXTextArea", secure: false, editable: true))
        XCTAssertTrue(TextInsertion.canRetarget(role: "AXTextField", secure: false, editable: true))
        XCTAssertFalse(TextInsertion.canRetarget(role: "AXTextField", secure: true, editable: true))
        XCTAssertFalse(TextInsertion.canRetarget(role: "AXWebArea", secure: false, editable: true))
        XCTAssertFalse(TextInsertion.canRetarget(role: "AXTextArea", secure: false, editable: false))
        XCTAssertTrue(TextInsertion.canRetarget(role: "AXTextArea", secure: false, editable: false, bundleID: "com.apple.Terminal"))
        XCTAssertTrue(TextInsertion.canRetarget(role: "AXTextArea", secure: false, editable: false, bundleID: "com.googlecode.iterm2"))
        XCTAssertFalse(TextInsertion.canRetarget(role: "AXButton", secure: false, editable: false, bundleID: "com.apple.Terminal"))
        XCTAssertFalse(TextInsertion.canRetarget(role: "AXTextArea", secure: true, editable: false, bundleID: "com.apple.Terminal"))
    }
    @MainActor func testOnlyEditableSelectionDeletes() {
        XCTAssertTrue(SmartPaste.shouldDelete(editable: true, selectionLength: 4))
        XCTAssertFalse(SmartPaste.shouldDelete(editable: true, selectionLength: 0))
        XCTAssertFalse(SmartPaste.shouldDelete(editable: false, selectionLength: 4))
        XCTAssertFalse(SmartPaste.shouldDelete(editable: false, selectionLength: 0))
    }
}
