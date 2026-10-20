import XCTest
@testable import GradientChat

final class AuthErrorMappingTests: XCTestCase {
    func testKnownCodesMapToTypedErrors() {
        XCTAssertEqual(WidgetBridge.authError(for: "resource_exhausted"), .rateLimited)
        XCTAssertEqual(WidgetBridge.authError(for: "session_invalid"), .sessionInvalid)
    }

    func testUnknownCodesArePreservedForLogs() {
        XCTAssertEqual(WidgetBridge.authError(for: "bad_signature"), .unknown(code: "bad_signature"))
        XCTAssertEqual(WidgetBridge.authError(for: ""), .unknown(code: ""))
    }

    func testLifecycleEventMapping() {
        XCTAssertEqual(WidgetBridge.lifecycleEvent(forStatus: "observing"), .handedOff)
        XCTAssertEqual(WidgetBridge.lifecycleEvent(forStatus: "finished"), .ended)
        XCTAssertEqual(WidgetBridge.lifecycleEvent(forStatus: "discarded"), .ended)
        XCTAssertEqual(WidgetBridge.lifecycleEvent(forStatus: "cancelled"), .ended)
        XCTAssertEqual(WidgetBridge.lifecycleEvent(forStatus: "failed"), .ended)
        // An active conversation and unrecognised statuses aren't lifecycle
        // transitions, so they produce no event.
        XCTAssertNil(WidgetBridge.lifecycleEvent(forStatus: "active"))
        XCTAssertNil(WidgetBridge.lifecycleEvent(forStatus: "anything-else"))
    }

    func testSenderMapping() {
        XCTAssertEqual(WidgetBridge.sender(for: "customer"), .customer)
        XCTAssertEqual(WidgetBridge.sender(for: "agent"), .agent)
        XCTAssertEqual(WidgetBridge.sender(for: "ai"), .ai)
        XCTAssertEqual(WidgetBridge.sender(for: ""), .ai)
    }
}
