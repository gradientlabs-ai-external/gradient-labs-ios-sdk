import Foundation

/// A chat lifecycle event, delivered to ``GradientChatListener/onChatEvent(_:)``.
public enum GradientChatEvent: Equatable, Sendable {
    /// A conversation became active.
    case started(conversationId: String, internalId: String)

    /// The conversation was handed off to a human agent.
    case handedOff

    /// A new message arrived — id and sender only, no body.
    case messageReceived(messageId: String, sender: Sender)

    /// The conversation ended.
    case ended

    /// The customer answered the end-of-conversation CSAT survey. Carries the
    /// answer to "Was your issue resolved?" only — the free-text follow-up
    /// never crosses the bridge.
    case surveySubmitted(resolved: Bool)

    /// The customer tapped a deep link rendered by an interactive tool. The
    /// host should open its native flow, then call
    /// ``GradientChat/completeInteractiveTool(requestID:result:)``.
    case deeplinkRequested(requestID: String, url: URL)

    /// Who sent a ``messageReceived(messageId:sender:)``.
    public enum Sender: Equatable, Sendable {
        case ai, agent, customer
    }
}
