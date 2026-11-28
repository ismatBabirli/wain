import XCTest
@testable import Wain

/// A MetricKit call stack in the shape `MXCallStackTree.jsonRepresentation()` gives: each frame's
/// first sub-frame is its caller. The simulator delivers no real crash, so this stands in for one.
final class AnalyticsTests: XCTestCase {
    private let stack = """
    {"callStackPerThread": true, "callStacks": [
      {"threadAttributed": false, "callStackRootFrames": [
        {"binaryName": "Wain", "offsetIntoBinaryTextSegment": 36864, "address": 1, "sampleCount": 1}]},
      {"threadAttributed": true, "callStackRootFrames": [
        {"binaryName": "libswiftCore.dylib", "offsetIntoBinaryTextSegment": 165304, "address": 2, "sampleCount": 1, "subFrames": [
          {"binaryName": "Wain", "offsetIntoBinaryTextSegment": 4096, "address": 3, "sampleCount": 1, "subFrames": [
            {"binaryName": "Wain", "offsetIntoBinaryTextSegment": 8192, "address": 4, "sampleCount": 1, "subFrames": [
              {"binaryName": "UIKitCore", "offsetIntoBinaryTextSegment": 12, "address": 5, "sampleCount": 1}]}]}]}]}
    ]}
    """.data(using: .utf8)!

    private func exception(_ props: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap((props["$exception_list"] as? [[String: Any]])?.first)
    }

    func testKeepsTheCrashedThreadsOwnFramesOutermostFirst() throws {
        let props = Analytics.crash(exception: 6, signal: 5, objcName: nil, stack: stack, binary: "Wain", version: "0.2.0", build: "41")
        let e = try exception(props)
        XCTAssertEqual(e["type"] as? String, "EXC_BREAKPOINT (SIGTRAP)")
        XCTAssertEqual(e["value"] as? String, "crash at Wain+0x1000")
        let frames = try XCTUnwrap((e["stacktrace"] as? [String: Any])?["frames"] as? [[String: Any]])
        XCTAssertEqual(frames.map { $0["function"] as? String }, ["0x2000", "0x1000"])
        XCTAssertEqual(frames.first?["platform"] as? String, "custom")
        XCTAssertEqual(props["build"] as? String, "41")
        XCTAssertEqual(props["kind"] as? String, "crash")
    }

    func testAnObjectiveCExceptionIsNamedOnlyByAnIdentifier() throws {
        let named = Analytics.crash(exception: 10, signal: 6, objcName: "NSInvalidArgumentException", stack: stack, binary: "Wain", version: nil, build: nil)
        XCTAssertEqual(try exception(named)["type"] as? String, "NSInvalidArgumentException")
        // A name is the thrower's own text, so one that could carry a path is never sent.
        let odd = Analytics.crash(exception: 10, signal: 6, objcName: "could not open /Users/me/x", stack: stack, binary: "Wain", version: nil, build: nil)
        XCTAssertEqual(try exception(odd)["type"] as? String, "EXC_CRASH (SIGABRT)")
    }

    func testAnUnreadableStackStillReportsTheType() throws {
        let props = Analytics.crash(exception: nil, signal: 99, objcName: nil, stack: Data(), binary: "Wain", version: nil, build: nil)
        let e = try exception(props)
        XCTAssertEqual(e["type"] as? String, "EXC_? (SIG99)")
        XCTAssertEqual(e["value"] as? String, "crash")
    }
}
