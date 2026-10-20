import WebKit

extension ChatViewController {
    func completeInteractiveTool(
        requestID: String,
        resultJSON: String,
        completion: @escaping InteractiveToolCompletionCoordinator.Completion
    ) {
        let request = InteractiveToolCompletionCoordinator.Request(
            requestID: requestID,
            resultJSON: resultJSON
        )
        guard interactiveToolCompletions.begin(request: request, completion: completion) else { return }
        dispatchInteractiveToolCompletion(request)
    }

    func interactiveToolCompletionReceived(requestID: String, accepted: Bool, errorCode: String?) {
        interactiveToolCompletions.resolve(
            requestID: requestID,
            accepted: accepted,
            errorCode: errorCode
        )
    }

    func redispatchPendingInteractiveToolCompletions() {
        interactiveToolCompletions.requests.forEach(dispatchInteractiveToolCompletion)
    }

    private func dispatchInteractiveToolCompletion(
        _ request: InteractiveToolCompletionCoordinator.Request
    ) {
        guard let webView,
              let attempt = interactiveToolCompletions.nextDispatchAttempt(requestID: request.requestID)
        else { return }
        let script = """
        typeof window.GradientWidget?.completeInteractiveTool === 'function' && \
        window.GradientWidget.completeInteractiveTool(\(WidgetURL.jsString(request.requestID)), \
        \(request.resultJSON)) === true
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    GradientChat.log.warning(
                        "Interactive tool JavaScript dispatch failed: \(error.localizedDescription, privacy: .public)"
                    )
                    self.interactiveToolCompletions.failDispatch(
                        requestID: request.requestID,
                        attempt: attempt,
                        error: .javascriptEvaluationFailed
                    )
                    return
                }
                guard value as? Bool == true else {
                    self.interactiveToolCompletions.failDispatch(
                        requestID: request.requestID,
                        attempt: attempt,
                        error: .widgetUnavailable
                    )
                    return
                }
                // Dispatch only starts the widget operation. The request stays
                // pending until its backend acknowledgement crosses the bridge.
            }
        }
    }
}
