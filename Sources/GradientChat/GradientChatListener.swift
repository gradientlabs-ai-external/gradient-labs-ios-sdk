import Foundation

/// Why the widget's session could not be established or was lost.
public enum GradientChatAuthError: Equatable, Sendable {
    /// /widget-sessions is rate-limited. Back off before re-minting — re-minting
    /// immediately just hits the limit again.
    case rateLimited

    /// The session is no longer valid; mint a fresh customer JWT.
    case sessionInvalid

    /// Any other auth failure. `code` is the raw widget error code, for logs.
    case unknown(code: String)
}

/// Why the chat can't be shown (not auth — that's ``GradientChatAuthError``).
public enum GradientChatUnavailableReason: Equatable, Sendable {
    /// The service reported it can't take the conversation right now (a problem
    /// on our side). The host can hide the entry point or show a fallback.
    case notAvailable

    /// The chat WebView failed to load the widget (main-frame load error, e.g.
    /// no network), leaving it blank until the user retries.
    case failedToLoad
}

/// Callbacks from the SDK. All methods are invoked on the main thread.
///
/// Listeners are held weakly: keep a strong reference for as long as you want
/// callbacks (e.g. on your app delegate or a long-lived model object).
public protocol GradientChatListener: AnyObject {
    /// The widget's session could not be established or is no longer valid. The
    /// host should mint a fresh customer JWT and pass it to
    /// ``GradientChat/setUserJwt(_:conversationToken:)`` (respecting backoff for
    /// ``GradientChatAuthError/rateLimited``).
    func onAuthError(_ error: GradientChatAuthError)

    /// A chat lifecycle event occurred.
    func onChatEvent(_ event: GradientChatEvent)

    /// The chat can't be shown. See ``GradientChatUnavailableReason``. The host
    /// can hide the entry point or surface its own fallback UI.
    func onChatUnavailable(_ reason: GradientChatUnavailableReason)
}

public extension GradientChatListener {
    func onAuthError(_ error: GradientChatAuthError) {}

    func onChatEvent(_ event: GradientChatEvent) {}

    func onChatUnavailable(_ reason: GradientChatUnavailableReason) {}
}
