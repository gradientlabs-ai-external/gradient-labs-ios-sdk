import WebKit

/// Receives widget → native messages. The widget posts to
/// `window.GradientChatNativeBridge.postMessage(json)` when that object exists;
/// `userScript` installs it before any widget code runs and forwards to the
/// WKWebView message handler.
final class WidgetBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "GradientChatNativeBridge"

    static let userScriptSource = """
    window.GradientChatNativeBridge = {
      postMessage: function (message) {
        window.webkit.messageHandlers.GradientChatNativeBridge.postMessage(message);
      }
    };
    """

    private static let authErrorType = "gradient-widget:auth-error"
    private static let closeType = "gradient-widget:close"
    private static let conversationReadyType = "gradient-widget:conversation-ready"
    private static let statusChangeType = "gradient-widget:status-change"
    private static let messageReceivedType = "gradient-widget:message-received"
    private static let surveySubmittedType = "gradient-widget:survey-submitted"
    private static let unavailableType = "gradient-widget:unavailable"
    private static let themeChangeType = "gradient-widget:theme-change"
    private static let deeplinkRequestedType = "gradient-widget:deeplink-requested"
    private static let interactiveToolCompletionType = "gradient-widget:interactive-tool-completion"

    private let widgetOrigin: URL

    init(widgetOrigin: URL) {
        self.widgetOrigin = widgetOrigin
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // Only trust the widget's own main frame: an off-origin page that
        // somehow ended up in the WebView must not be able to drive the host
        // via the bridge.
        guard message.frameInfo.isMainFrame,
              originMatches(message.frameInfo.securityOrigin),
              let raw = message.body as? String,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return }

        switch type {
        case Self.authErrorType:
            let code = object["code"] as? String ?? ""
            let error = Self.authError(for: code)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GradientChat.dispatchAuthError(error)
                }
            }
        case Self.closeType:
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GradientChat.closeRequested()
                }
            }
        case Self.conversationReadyType:
            let started = GradientChatEvent.started(
                conversationId: object["external_id"] as? String ?? "",
                internalId: object["internal_id"] as? String ?? ""
            )
            // A resumed conversation reports its current status; replay the
            // lifecycle event it implies so the host learns it was handed off
            // or ended without a separate status-change.
            let lifecycle = Self.lifecycleEvent(forStatus: object["status"] as? String ?? "")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GradientChat.dispatchEvent(started)
                    if let lifecycle {
                        GradientChat.dispatchEvent(lifecycle)
                    }
                }
            }
        case Self.statusChangeType:
            guard let lifecycle = Self.lifecycleEvent(forStatus: object["status"] as? String ?? "")
            else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GradientChat.dispatchEvent(lifecycle)
                }
            }
        case Self.messageReceivedType:
            let event = GradientChatEvent.messageReceived(
                messageId: object["message_id"] as? String ?? "",
                sender: Self.sender(for: object["sender"] as? String ?? "")
            )
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GradientChat.dispatchEvent(event)
                }
            }
        case Self.surveySubmittedType:
            let event = GradientChatEvent.surveySubmitted(
                resolved: object["resolved"] as? Bool ?? false
            )
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GradientChat.dispatchEvent(event)
                }
            }
        case Self.unavailableType:
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GradientChat.dispatchUnavailable(.notAvailable)
                }
            }
        case Self.themeChangeType:
            let isDark = (object["theme"] as? String) == "dark"
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GradientChat.widgetThemeChanged(isDark: isDark)
                }
            }
        case Self.deeplinkRequestedType:
            Self.dispatchDeeplink(from: object)
        case Self.interactiveToolCompletionType:
            Self.dispatchInteractiveToolCompletion(from: object)
        default:
            break
        }
    }

    static func authError(for code: String) -> GradientChatAuthError {
        switch code {
        case "resource_exhausted": return .rateLimited
        case "session_invalid": return .sessionInvalid
        default: return .unknown(code: code)
        }
    }

    /// Map the widget's backend status strings to the lifecycle event they
    /// imply, or nil for statuses that aren't a lifecycle transition (an active
    /// conversation, or an unrecognised status).
    static func lifecycleEvent(forStatus status: String) -> GradientChatEvent? {
        switch status {
        case "observing": return .handedOff
        case "finished", "discarded", "cancelled", "failed": return .ended
        default: return nil
        }
    }

    static func sender(for sender: String) -> GradientChatEvent.Sender {
        switch sender {
        case "customer": return .customer
        case "agent": return .agent
        default: return .ai
        }
    }

    static func deeplinkEvent(requestID: String, rawURL: String) -> GradientChatEvent? {
        guard !requestID.isEmpty,
              let url = URL(string: rawURL),
              url.scheme != nil
        else { return nil }
        return .deeplinkRequested(requestID: requestID, url: url)
    }

    private static func dispatchDeeplink(from object: [String: Any]) {
        guard let event = deeplinkEvent(
            requestID: object["request_id"] as? String ?? "",
            rawURL: object["url"] as? String ?? ""
        ) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                GradientChat.dispatchEvent(event)
            }
        }
    }

    struct InteractiveToolCompletion: Equatable {
        let requestID: String
        let accepted: Bool
        let errorCode: String?
    }

    static func interactiveToolCompletion(
        requestID: String,
        accepted: Bool?,
        errorCode: String?
    ) -> InteractiveToolCompletion? {
        guard !requestID.isEmpty, let accepted else { return nil }
        return InteractiveToolCompletion(
            requestID: requestID,
            accepted: accepted,
            errorCode: errorCode
        )
    }

    private static func dispatchInteractiveToolCompletion(from object: [String: Any]) {
        guard let completion = interactiveToolCompletion(
            requestID: object["request_id"] as? String ?? "",
            accepted: object["accepted"] as? Bool,
            errorCode: object["error_code"] as? String
        ) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                GradientChat.interactiveToolCompletionReceived(
                    requestID: completion.requestID,
                    accepted: completion.accepted,
                    errorCode: completion.errorCode
                )
            }
        }
    }

    private func originMatches(_ origin: WKSecurityOrigin) -> Bool {
        let port = origin.port == 0
            ? ChatNavigationPolicy.effectivePort(widgetOrigin)
            : origin.port
        return origin.protocol.lowercased() == widgetOrigin.scheme?.lowercased()
            && origin.host.lowercased() == widgetOrigin.host?.lowercased()
            && port == ChatNavigationPolicy.effectivePort(widgetOrigin)
    }
}
