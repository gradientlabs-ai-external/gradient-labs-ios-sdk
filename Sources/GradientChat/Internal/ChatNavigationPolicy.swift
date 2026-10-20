import Foundation

/// Pure origin / URL logic for the chat WebView's navigation decisions.
enum ChatNavigationPolicy {
    /// Compare parsed scheme+host+effective-port, not a string prefix: a
    /// navigation to the bare origin (no trailing slash) must not be treated
    /// as off-origin.
    static func isSameOrigin(_ url: URL, as origin: URL) -> Bool {
        url.scheme?.lowercased() == origin.scheme?.lowercased()
            && url.host?.lowercased() == origin.host?.lowercased()
            && effectivePort(url) == effectivePort(origin)
    }

    static func effectivePort(_ url: URL) -> Int {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return -1
        }
    }

    /// Widget URLs carry the user JWT in the fragment; it must never leak to
    /// an external app.
    static func strippingFragment(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }
}
