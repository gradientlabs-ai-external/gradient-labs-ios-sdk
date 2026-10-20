import WebKit

/// WKUserContentController retains its message handlers, which would keep the
/// chat view controller (and its WebView) alive after dismissal. This wrapper
/// holds the real handler weakly so the retain cycle is broken.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
