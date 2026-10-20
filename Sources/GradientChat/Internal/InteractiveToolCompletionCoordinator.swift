import Foundation

@MainActor
final class InteractiveToolCompletionCoordinator {
    struct Request: Equatable {
        let requestID: String
        let resultJSON: String
    }

    typealias Completion = (Result<Void, GradientChatInteractiveToolError>) -> Void

    private struct PendingRequest {
        let request: Request
        let completion: Completion
        var dispatchAttempt = 0
    }

    private var pending: [String: PendingRequest] = [:]

    var requests: [Request] {
        pending.values.map(\.request)
    }

    func begin(request: Request, completion: @escaping Completion) -> Bool {
        guard pending[request.requestID] == nil else {
            completion(.failure(.completionAlreadyPending(requestID: request.requestID)))
            return false
        }
        pending[request.requestID] = PendingRequest(request: request, completion: completion)
        return true
    }

    func nextDispatchAttempt(requestID: String) -> Int? {
        guard var pendingRequest = pending[requestID] else { return nil }
        pendingRequest.dispatchAttempt += 1
        pending[requestID] = pendingRequest
        return pendingRequest.dispatchAttempt
    }

    func resolve(requestID: String, accepted: Bool, errorCode: String?) {
        guard let pendingRequest = pending.removeValue(forKey: requestID) else { return }
        if accepted {
            pendingRequest.completion(.success(()))
        } else {
            pendingRequest.completion(.failure(.completionRejected(errorCode: errorCode)))
        }
    }

    func failDispatch(
        requestID: String,
        attempt: Int,
        error: GradientChatInteractiveToolError
    ) {
        guard pending[requestID]?.dispatchAttempt == attempt else { return }
        pending.removeValue(forKey: requestID)?.completion(.failure(error))
    }

    func failAll(with error: GradientChatInteractiveToolError) {
        let requests = Array(pending.values)
        pending.removeAll()
        requests.forEach { $0.completion(.failure(error)) }
    }
}
