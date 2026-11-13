import XCTest
@testable import JotCore

final class MixdownTests: XCTestCase {
    func testSumsChannelsAndClamps() {
        let mic: [Float] = [0.1, 0.5, -0.9, 0]
        let left: [Float] = [0.2, 0.4, -0.5, 0]
        let right: [Float] = [0.2, 0.4, 0, 0.3]
        var out = [Float](repeating: 9, count: 4)
        mic.withUnsafeBufferPointer { m in left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in
            out.withUnsafeMutableBufferPointer { o in mixToMono([m.baseAddress!, l.baseAddress!, r.baseAddress!], frames: 4, into: o.baseAddress!) }
        } } }
        XCTAssertEqual(out[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(out[1], 1, accuracy: 1e-6)   // 1.3 clamped
        XCTAssertEqual(out[2], -1, accuracy: 1e-6)  // -1.4 clamped
        XCTAssertEqual(out[3], 0.3, accuracy: 1e-6)
    }
}
