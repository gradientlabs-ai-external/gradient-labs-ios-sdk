import Foundation

/// Identifies the company (via `widgetKey`) and the end user (via `userJwt`,
/// a short-lived identity-only HS256 JWT minted by the customer's backend).
///
/// `conversationToken` is an optional conversation-scope token carried
/// alongside the JWT (never inside it); the backend tokenizes it at session
/// mint and replays it to the customer on tool/webhook calls. nil leaves any
/// previously stored value unchanged; "" explicitly clears it.
///
/// `tags` label a new conversation and are ignored when an existing one resumes.
public struct GradientChatConfig: Sendable {
    public let widgetKey: String
    public let userJwt: String
    public let conversationToken: String?
    public let tags: [String]

    public init(widgetKey: String, userJwt: String, conversationToken: String? = nil, tags: [String] = []) {
        self.widgetKey = widgetKey
        self.userJwt = userJwt
        self.conversationToken = conversationToken
        self.tags = tags
    }
}

/// Debug-only overrides for local development. Production integrations never
/// construct this — the SDK targets Gradient's production widget + API by
/// default. Used by the sample harness to point at a local widget / backend
/// and exercise short-lived sessions.
public struct GradientChatDebugConfig: Sendable {
    /// Override the widget origin (e.g. "http://localhost:5173"). nil → production.
    public var widgetOrigin: String?
    /// Ask the backend to mint 15s sessions to test the expiry path.
    public var shortSession: Bool

    public init(widgetOrigin: String? = nil, shortSession: Bool = false) {
        self.widgetOrigin = widgetOrigin
        self.shortSession = shortSession
    }
}
