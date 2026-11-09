import Foundation

/// Builds the widget load URL. The JWT travels in the URL fragment so it never
/// reaches server logs or Referer headers; the widget reads it synchronously on
/// mount and scrubs it via history.replaceState.
enum WidgetURL {
    /// "{origin}/#jwt={jwt}" plus "&use_short_session=1" when testing expiry.
    /// The JWT is base64url so it needs no percent-encoding in a fragment.
    ///
    /// A non-empty `conversationToken` adds "&conversation_token={value}" (sent
    /// as a separate body field on the widget's session exchange, never inside
    /// the JWT). nil or "" omits the parameter, leaving any stored value
    /// unchanged.
    ///
    /// Each tag adds "&tag={value}"; the widget sanitises them.
    ///
    /// "&platform=ios" always comes last and tells the widget which app it is
    /// running in.
    static func fragment(jwt: String, conversationToken: String?, tags: [String], shortSession: Bool) -> String {
        var fragment = "#jwt=\(jwt)"
        if let conversationToken, !conversationToken.isEmpty {
            fragment += "&conversation_token=\(percentEncoded(conversationToken))"
        }
        for tag in tags {
            fragment += "&tag=\(percentEncoded(tag))"
        }
        if shortSession {
            fragment += "&use_short_session=1"
        }
        fragment += "&platform=ios"
        return fragment
    }

    static func load(
        origin: String,
        jwt: String,
        conversationToken: String?,
        tags: [String],
        shortSession: Bool
    ) -> URL? {
        let fragment = fragment(jwt: jwt, conversationToken: conversationToken, tags: tags, shortSession: shortSession)
        return URL(string: "\(origin)/\(fragment)")
    }

    /// Conversation tokens and tags are opaque host values, so percent-encode
    /// them to keep arbitrary characters from breaking the fragment.
    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// Single-quoted JS string literal, escaped so a hostile value can't break
    /// out of the quotes when passed to evaluateJavaScript.
    static func jsString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "'\(escaped)'"
    }
}
