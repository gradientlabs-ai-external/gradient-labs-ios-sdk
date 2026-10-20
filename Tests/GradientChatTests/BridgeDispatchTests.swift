import XCTest
@testable import GradientChat

/// Records the callbacks the SDK delivers, so tests can assert what the bridge
/// mapping produced end to end.
private final class RecordingListener: GradientChatListener {
    var events: [GradientChatEvent] = []
    var unavailableReasons: [GradientChatUnavailableReason] = []

    func onChatEvent(_ event: GradientChatEvent) {
        events.append(event)
    }

    func onChatUnavailable(_ reason: GradientChatUnavailableReason) {
        unavailableReasons.append(reason)
    }
}

@MainActor
final class BridgeDispatchTests: XCTestCase {
    private var listener: RecordingListener!

    override func setUp() {
        super.setUp()
        listener = RecordingListener()
        GradientChat.addListener(listener)
    }

    override func tearDown() {
        GradientChat.removeListener(listener)
        listener = nil
        super.tearDown()
    }

    func testUnavailableMessageMapsToNotAvailable() {
        // gradient-widget:unavailable → onChatUnavailable(.notAvailable)
        GradientChat.dispatchUnavailable(.notAvailable)
        XCTAssertEqual(listener.unavailableReasons, [.notAvailable])
    }

    func testMainFrameLoadFailureMapsToFailedToLoad() {
        // A main-frame load error routes through onChatUnavailable(.failedToLoad).
        GradientChat.dispatchUnavailable(.failedToLoad)
        XCTAssertEqual(listener.unavailableReasons, [.failedToLoad])
    }

    func testObservingStatusEmitsHandedOff() {
        let event = WidgetBridge.lifecycleEvent(forStatus: "observing")
        XCTAssertEqual(event, .handedOff)
        event.map { GradientChat.dispatchEvent($0) }
        XCTAssertEqual(listener.events, [.handedOff])
    }

    func testFinishedStatusEmitsEnded() {
        let event = WidgetBridge.lifecycleEvent(forStatus: "finished")
        XCTAssertEqual(event, .ended)
        event.map { GradientChat.dispatchEvent($0) }
        XCTAssertEqual(listener.events, [.ended])
    }

    func testDeeplinkMessageEmitsRequest() throws {
        let url = try XCTUnwrap(URL(string: "gradientsample://track_paycheck"))
        let event = try XCTUnwrap(WidgetBridge.deeplinkEvent(
            requestID: "async_tool_execution_1",
            rawURL: url.absoluteString
        ))

        XCTAssertEqual(
            event,
            .deeplinkRequested(requestID: "async_tool_execution_1", url: url)
        )
        GradientChat.dispatchEvent(event)
        XCTAssertEqual(listener.events, [event])
    }

    func testDeeplinkMessageRejectsMissingRequestIDAndRelativeURL() {
        XCTAssertNil(WidgetBridge.deeplinkEvent(
            requestID: "",
            rawURL: "gradientsample://track_paycheck"
        ))
        XCTAssertNil(WidgetBridge.deeplinkEvent(
            requestID: "async_tool_execution_1",
            rawURL: "/track_paycheck"
        ))
    }

    func testInteractiveToolCompletionMessageMapsAcknowledgement() {
        XCTAssertEqual(
            WidgetBridge.interactiveToolCompletion(
                requestID: "async_tool_execution_1",
                accepted: true,
                errorCode: nil
            ),
            WidgetBridge.InteractiveToolCompletion(
                requestID: "async_tool_execution_1",
                accepted: true,
                errorCode: nil
            )
        )
        XCTAssertEqual(
            WidgetBridge.interactiveToolCompletion(
                requestID: "async_tool_execution_1",
                accepted: false,
                errorCode: "request_failed"
            ),
            WidgetBridge.InteractiveToolCompletion(
                requestID: "async_tool_execution_1",
                accepted: false,
                errorCode: "request_failed"
            )
        )
    }

    func testInteractiveToolCompletionMessageRequiresIDAndAccepted() {
        XCTAssertNil(WidgetBridge.interactiveToolCompletion(
            requestID: "",
            accepted: true,
            errorCode: nil
        ))
        XCTAssertNil(WidgetBridge.interactiveToolCompletion(
            requestID: "async_tool_execution_1",
            accepted: nil,
            errorCode: nil
        ))
    }
}
