import XCTest
@testable import GradientChat

@MainActor
final class InteractiveToolCompletionTests: XCTestCase {
    func testAcceptedAcknowledgementCompletesPendingRequest() {
        let coordinator = InteractiveToolCompletionCoordinator()
        var result: Result<Void, GradientChatInteractiveToolError>?
        let request = InteractiveToolCompletionCoordinator.Request(
            requestID: "async_tool_execution_1",
            resultJSON: #"{"status":"completed"}"#
        )

        XCTAssertTrue(coordinator.begin(request: request) { result = $0 })
        XCTAssertEqual(coordinator.requests, [request])

        coordinator.resolve(requestID: request.requestID, accepted: true, errorCode: nil)

        XCTAssertNotNil(try? result?.get())
        XCTAssertTrue(coordinator.requests.isEmpty)
    }

    func testRejectedAcknowledgementFailsAndAllowsRetry() {
        let coordinator = InteractiveToolCompletionCoordinator()
        var firstResult: Result<Void, GradientChatInteractiveToolError>?
        let request = InteractiveToolCompletionCoordinator.Request(
            requestID: "async_tool_execution_1",
            resultJSON: #"{"status":"completed"}"#
        )

        XCTAssertTrue(coordinator.begin(request: request) { firstResult = $0 })
        coordinator.resolve(
            requestID: request.requestID,
            accepted: false,
            errorCode: "request_failed"
        )

        XCTAssertEqual(
            firstResult?.failure,
            .completionRejected(errorCode: "request_failed")
        )
        XCTAssertTrue(coordinator.begin(request: request) { _ in })
    }

    func testDuplicatePendingRequestFailsWithoutReplacingOriginal() {
        let coordinator = InteractiveToolCompletionCoordinator()
        var duplicateResult: Result<Void, GradientChatInteractiveToolError>?
        let request = InteractiveToolCompletionCoordinator.Request(
            requestID: "async_tool_execution_1",
            resultJSON: #"{"status":"completed"}"#
        )

        XCTAssertTrue(coordinator.begin(request: request) { _ in })
        XCTAssertFalse(coordinator.begin(request: request) { duplicateResult = $0 })

        XCTAssertEqual(
            duplicateResult?.failure,
            .completionAlreadyPending(requestID: request.requestID)
        )
        XCTAssertEqual(coordinator.requests, [request])
    }

    func testFailAllFailsEveryPendingRequest() {
        let coordinator = InteractiveToolCompletionCoordinator()
        var failures: [GradientChatInteractiveToolError] = []

        for requestID in ["async_tool_execution_1", "async_tool_execution_2"] {
            let request = InteractiveToolCompletionCoordinator.Request(
                requestID: requestID,
                resultJSON: #"{"status":"completed"}"#
            )
            XCTAssertTrue(coordinator.begin(request: request) { result in
                if case .failure(let error) = result { failures.append(error) }
            })
        }

        coordinator.failAll(with: .chatNotPresented)

        XCTAssertEqual(failures, [.chatNotPresented, .chatNotPresented])
        XCTAssertTrue(coordinator.requests.isEmpty)
    }

    func testFailureFromStaleWebViewDispatchIsIgnored() throws {
        let coordinator = InteractiveToolCompletionCoordinator()
        var result: Result<Void, GradientChatInteractiveToolError>?
        let request = InteractiveToolCompletionCoordinator.Request(
            requestID: "async_tool_execution_1",
            resultJSON: #"{"status":"completed"}"#
        )
        XCTAssertTrue(coordinator.begin(request: request) { result = $0 })
        let staleAttempt = try XCTUnwrap(coordinator.nextDispatchAttempt(requestID: request.requestID))
        _ = coordinator.nextDispatchAttempt(requestID: request.requestID)

        coordinator.failDispatch(
            requestID: request.requestID,
            attempt: staleAttempt,
            error: .javascriptEvaluationFailed
        )

        XCTAssertNil(result)
        XCTAssertEqual(coordinator.requests, [request])
    }
}

private extension Result {
    var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
