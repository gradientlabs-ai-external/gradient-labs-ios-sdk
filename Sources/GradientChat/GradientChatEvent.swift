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

    /// The customer tapped a link into the host app. With a `requestID` an
    /// interactive tool is waiting: open the native flow, then call
    /// ``GradientChat/completeInteractiveTool(requestID:result:)``. Without
    /// one (a link in an agent reply), just open the screen. Either way the
    /// host chooses to present it over the chat or call
    /// ``GradientChat/dismiss(animated:)`` first.
    case deeplinkRequested(requestID: String?, url: URL)

    /// Who sent a ``messageReceived(messageId:sender:)``.
    public enum Sender: Equatable, Sendable {
        case ai, agent, customer
    }
}
