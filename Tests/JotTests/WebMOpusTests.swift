import XCTest
@testable import JotCore

final class WebMOpusTests: XCTestCase {
    private func element(_ id: [UInt8], _ body: [UInt8]) -> [UInt8] { id + [0x80 | UInt8(body.count)] + body }
    func testLiveRecordingWithUnknownSizesKeepsOnlyOpusFrames() throws {
        let unknown: [UInt8] = [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        let opusHead = Array("OpusHead".utf8) + [1, 2, 0x38, 0x01, 0x80, 0xBB, 0, 0, 0, 0, 0]
        var file = element([0x1A, 0x45, 0xDF, 0xA3], element([0x42, 0x82], Array("webm".utf8)))
        file += [0x18, 0x53, 0x80, 0x67] + unknown
        file += element([0xEC], [0, 0, 0]) // Void
        file += element([0x16, 0x54, 0xAE, 0x6B], element([0xAE], element([0xD7], [1]) + element([0x86], Array("A_OPUS".utf8)) + element([0x63, 0xA2], opusHead)))
        file += [0x1F, 0x43, 0xB6, 0x75] + unknown + element([0xE7], [0])
        file += element([0xA3], [0x81, 0, 0, 0x80, 0xFC, 1, 2, 3])
        file += element([0xA3], [0x82, 0, 20, 0x80, 0xFC, 9]) // another track
        file += element([0xA0], element([0xA1], [0x81, 0, 40, 0x00, 0xFC, 4]))
        file += [0xA3, 0x90, 0x81] // truncated tail
        let parsed = try WebMOpus.parse(Data(file))
        XCTAssertEqual(parsed.channels, 2)
        XCTAssertEqual(parsed.packets, [Data([0xFC, 1, 2, 3]), Data([0xFC, 4])])
    }
    func testNonOpusWebMIsRejected() {
        let file = element([0x16, 0x54, 0xAE, 0x6B], element([0xAE], element([0xD7], [1]) + element([0x86], Array("A_VORBIS".utf8))))
        XCTAssertThrowsError(try WebMOpus.parse(Data(file)))
    }
    func testOpusPacketDurationFromTOC() {
        XCTAssertEqual(WebMOpus.frames(Data([0xFC])), 960)        // CELT 20 ms, one frame
        XCTAssertEqual(WebMOpus.frames(Data([0x18])), 2880)       // SILK 60 ms
        XCTAssertEqual(WebMOpus.frames(Data([0x79])), 1920)       // hybrid 20 ms, two frames
        XCTAssertEqual(WebMOpus.frames(Data([0xE3, 0x03])), 360)  // CELT 2.5 ms, three frames
        XCTAssertEqual(WebMOpus.frames(Data()), 0)
    }
}
