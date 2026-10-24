import os
import UIKit

public enum GradientChatInteractiveToolError: Error, Equatable, Sendable {
    case chatNotPresented
    case resultMustBeJSONObject
    case completionAlreadyPending(requestID: String)
    case widgetUnavailable
    case javascriptEvaluationFailed
    case completionRejected(errorCode: String?)
}

@MainActor
public enum GradientChat {
    static let log = Logger(subsystem: "com.gradientlabs.chat-sdk", category: "GradientChat")

    private static let prodWidgetOrigin = "https://chat-sdk-widget.vercel.app"

    private static var config: GradientChatConfig?
    private static var debugConfig: GradientChatDebugConfig?
    private static let listeners = NSHashTable<AnyObject>.weakObjects()
    private static weak var liveChat: ChatViewController?

    /// Initialise the SDK. Call once before presenting the chat (e.g. at app
    /// launch). `debug` is for local development only — omit in production.
    public static func boot(config: GradientChatConfig, debug: GradientChatDebugConfig? = nil) {
        self.config = config
        // Debug overrides are a trust boundary: an overridden widgetOrigin
        // receives the user JWT and the privileged WebView bridge. Only honour
        // them in DEBUG builds of the host app.
        #if DEBUG
        debugConfig = debug
        #else
        if debug != nil {
            log.warning("Ignoring GradientChatDebugConfig: this is not a DEBUG build.")
        }
        debugConfig = nil
        #endif
    }

    /// Opens the chat UI as a full-screen modal over `presenter`. `boot` must
    /// have been called first. No-op (with a warning) after `logout` until a
    /// fresh JWT is supplied via `setUserJwt` or `boot`. If the chat is already
    /// on screen, reloads only when the JWT changed.
    public static func present(from presenter: UIViewController) {
        guard let cfg = config else {
            preconditionFailure("GradientChat.boot(...) must be called before present(...)")
        }
        if cfg.userJwt.isEmpty {
            log.warning(
                """
                present() ignored: logout() cleared the user JWT. Provide a \
                fresh JWT via setUserJwt(...) or boot(...) first.
                """
            )
            return
        }
        if let live = liveChat {
            live.reload(ifChangedJwt: cfg.userJwt, conversationToken: cfg.conversationToken, tags: cfg.tags)
            return
        }
        let chat = ChatViewController(
            widgetOrigin: widgetOrigin(),
            jwt: cfg.userJwt,
            conversationToken: cfg.conversationToken,
            tags: cfg.tags,
            shortSession: shortSession()
        )
        liveChat = chat
        presenter.present(chat, animated: true)
    }

    /// Replace the user JWT (e.g. after re-minting on a ``GradientChatAuthError``,
    /// or when a user logs back in after `logout`). `conversationToken` rides
    /// alongside the JWT but travels as a separate field on the session
    /// exchange (never inside the JWT): nil (the default) or "" leaves the
    /// stored token unchanged; a non-empty value replaces it.
    public static func setUserJwt(_ jwt: String, conversationToken: String? = nil) {
        guard let current = config else {
            preconditionFailure("GradientChat.boot(...) must be called first")
        }
        let resolvedToken = conversationToken.flatMap { $0.isEmpty ? nil : $0 } ?? current.conversationToken
        config = GradientChatConfig(
            widgetKey: current.widgetKey,
            userJwt: jwt,
            conversationToken: resolvedToken,
            tags: current.tags
        )
        liveChat?.reload(ifChangedJwt: jwt, conversationToken: resolvedToken, tags: current.tags)
    }

    /// Register a listener for SDK callbacks (auth errors, load failures).
    /// Each registered listener receives every callback. Adding the same
    /// instance twice is a no-op. Listeners are held weakly — keep a strong
    /// reference for as long as you want callbacks.
    public static func addListener(_ listener: GradientChatListener) {
        listeners.add(listener)
    }

    /// Unregister a listener previously passed to `addListener`. No-op if not
    /// registered.
    public static func removeListener(_ listener: GradientChatListener) {
        listeners.remove(listener)
    }

    /// Complete a native flow started by an interactive tool. Returns only
    /// after the widget's backend has accepted the result. The result must
    /// encode as a JSON object and is delivered through the live widget's
    /// authenticated session. A failed call can be retried with the same
    /// request ID and result.
    public static func completeInteractiveTool<Payload: Encodable>(
        requestID: String,
        result: Payload
    ) async throws {
        guard let liveChat else {
            throw GradientChatInteractiveToolError.chatNotPresented
        }
        let data = try JSONEncoder().encode(result)
        guard (try JSONSerialization.jsonObject(with: data)) is [String: Any],
              let json = String(data: data, encoding: .utf8)
        else {
            throw GradientChatInteractiveToolError.resultMustBeJSONObject
        }
        try await withCheckedThrowingContinuation { continuation in
            liveChat.completeInteractiveTool(requestID: requestID, resultJSON: json) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Callback form of ``completeInteractiveTool(requestID:result:)``.
    public static func completeInteractiveTool<Payload: Encodable>(
        requestID: String,
        result: Payload,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task { @MainActor in
            do {
                try await completeInteractiveTool(requestID: requestID, result: result)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Call when the user logs out of the host app. Clears the user JWT (so
    /// `present` is a no-op until a fresh one is supplied) and closes the chat
    /// screen if it's open. Idempotent.
    public static func logout() {
        guard let current = config else {
            log.warning("logout() called before boot(); nothing to clear.")
            return
        }
        config = GradientChatConfig(widgetKey: current.widgetKey, userJwt: "")
        dismiss()
    }

    /// Closes the chat screen, along with anything presented over it, if it's
    /// open. Unlike `logout`, the JWT stays so the conversation resumes on the
    /// next `present`.
    public static func dismiss(animated: Bool = true) {
        liveChat?.presentingViewController?.dismiss(animated: animated)
        liveChat = nil
    }

    // MARK: - Internal

    static func widgetOrigin() -> String {
        debugConfig?.widgetOrigin ?? prodWidgetOrigin
    }

    static func shortSession() -> Bool {
        debugConfig?.shortSession ?? false
    }

    static func chatDismissed(_ chat: ChatViewController) {
        if liveChat === chat { liveChat = nil }
    }

    /// The widget resolved its effective theme; restyle the native chrome.
    static func widgetThemeChanged(isDark: Bool) {
        liveChat?.applyWidgetTheme(isDark: isDark)
    }

    /// The widget's in-header close button was tapped. Dismiss the chat
    /// screen; unlike `logout`, the JWT stays so the conversation resumes on
    /// the next `present`.
    static func closeRequested() {
        dismiss()
    }

    static func interactiveToolCompletionReceived(
        requestID: String,
        accepted: Bool,
        errorCode: String?
    ) {
        liveChat?.interactiveToolCompletionReceived(
            requestID: requestID,
            accepted: accepted,
            errorCode: errorCode
        )
    }

    static func dispatchAuthError(_ error: GradientChatAuthError) {
        for case let listener as GradientChatListener in listeners.allObjects {
            listener.onAuthError(error)
        }
    }

    static func dispatchEvent(_ event: GradientChatEvent) {
        for case let listener as GradientChatListener in listeners.allObjects {
            listener.onChatEvent(event)
        }
    }

    static func dispatchUnavailable(_ reason: GradientChatUnavailableReason) {
        for case let listener as GradientChatListener in listeners.allObjects {
            listener.onChatUnavailable(reason)
        }
    }
}
