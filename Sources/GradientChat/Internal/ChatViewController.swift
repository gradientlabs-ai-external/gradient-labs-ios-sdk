import UIKit
import WebKit

/// Full-screen chat screen: a WKWebView pointed at the hosted widget, plus a
/// floating close button (the widget has no close affordance of its own yet).
@MainActor
final class ChatViewController: UIViewController {
    private let widgetOriginString: String
    private let widgetOriginURL: URL?
    private let shortSession: Bool
    private var lastLoadedJwt: String
    private var lastLoadedConversationToken: String?
    private var mainFrameLoadFailed = false
    private var didMoveVoiceOverFocus = false
    let interactiveToolCompletions = InteractiveToolCompletionCoordinator()

    var webView: WKWebView?
    private var bridge: WidgetBridge?
    private var fallbackCloseButton: UIButton?

    init(widgetOrigin: String, jwt: String, conversationToken: String?, shortSession: Bool) {
        self.widgetOriginString = widgetOrigin
        self.widgetOriginURL = URL(string: widgetOrigin)
        self.lastLoadedJwt = jwt
        self.lastLoadedConversationToken = conversationToken
        self.shortSession = shortSession
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let configuration = WKWebViewConfiguration()
        // Persistent store so the widget's localStorage (conversation identity)
        // survives across presents and app launches.
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // iOS auto-zooms any focused input with a font size under 16px; the
        // widget's composer is 14px, so typing zooms the page out of the
        // frame. Pin the viewport scale — inside a native app the chat isn't
        // expected to pinch-zoom.
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                (function () {
                  var meta = document.querySelector('meta[name="viewport"]');
                  if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    document.head.appendChild(meta);
                  }
                  meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
                })();
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        // WKWebView ignores the OS text-size setting, so the widget's CSS reads
        // its scale from a --font-scale variable that we drive from Dynamic
        // Type. Seed it at document start (before first paint) and keep it in
        // sync on text-size changes below.
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.fontScaleScript(scale: dynamicTypeScale()),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )

        if let originURL = widgetOriginURL {
            let bridge = WidgetBridge(widgetOrigin: originURL)
            self.bridge = bridge
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: WidgetBridge.userScriptSource,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
            configuration.userContentController.add(
                WeakScriptMessageHandler(bridge),
                name: WidgetBridge.handlerName
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.keyboardDismissMode = .interactive
        // Transparent WebView: WebKit's default is an opaque white canvas,
        // which flashes before the widget paints and shows through overscroll
        // — glaring when the widget is dark. The container view behind it
        // tracks the widget's resolved theme (see applyWidgetTheme).
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        // The widget is a fixed full-viewport page with its own inner scroll
        // area, so the document itself never legitimately scrolls. Resize the
        // WebView with the keyboard (Android parity: the container is padded
        // by IME insets there) and pin the document offset so WebKit's
        // keyboard avoidance can't shove the header off-screen.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.delegate = self
        webView.removeInputAccessoryView()

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        // The widget renders its own close button (which posts
        // gradient-widget:close through the bridge). This native one exists
        // only for the state where the widget never loaded — without it a
        // main-frame load failure would trap the user in a full-screen modal.
        let fallback = makeCloseButton()
        fallback.isHidden = true
        fallbackCloseButton = fallback

        load(jwt: lastLoadedJwt, conversationToken: lastLoadedConversationToken)
    }

    /// Called when `present` finds the chat already on screen, and by
    /// `setUserJwt`. Reload only if the JWT or conversation token actually
    /// changed under us, otherwise keep the live conversation as-is. A nil
    /// `conversationToken` leaves the stored token unchanged; non-nil replaces it.
    func reload(ifChangedJwt jwt: String, conversationToken: String?) {
        let nextToken = conversationToken ?? lastLoadedConversationToken
        guard jwt != lastLoadedJwt || nextToken != lastLoadedConversationToken else { return }
        lastLoadedJwt = jwt
        lastLoadedConversationToken = nextToken
        guard let webView, !mainFrameLoadFailed else {
            load(jwt: jwt, conversationToken: nextToken)
            return
        }
        // A fragment assignment fires the widget's hashchange JWT path without
        // reloading the page, so the live conversation DOM is preserved.
        let fragment = WidgetURL.fragment(jwt: jwt, conversationToken: nextToken, shortSession: shortSession)
        webView.evaluateJavaScript(
            "location.hash = \(WidgetURL.jsString(fragment))",
            completionHandler: nil
        )
    }

    /// The widget resolved its theme (company setting or OS change). Match the
    /// container — it paints the safe-area strips around the transparent
    /// WebView — to the widget's surface color so the chrome reads as one.
    func applyWidgetTheme(isDark: Bool) {
        view.backgroundColor = isDark
            ? UIColor(red: 0x02 / 255.0, green: 0x06 / 255.0, blue: 0x17 / 255.0, alpha: 1)
            : .white
    }

    private func load(jwt: String, conversationToken: String?) {
        guard let url = WidgetURL.load(
            origin: widgetOriginString,
            jwt: jwt,
            conversationToken: conversationToken,
            shortSession: shortSession
        ) else {
            GradientChat.log.error("Invalid widget origin: \(self.widgetOriginString, privacy: .public)")
            return
        }
        mainFrameLoadFailed = false
        lastLoadedJwt = jwt
        lastLoadedConversationToken = conversationToken
        webView?.load(URLRequest(url: url))
    }

    // MARK: - Dynamic Type

    /// Maps the user's Dynamic Type setting to the widget's --font-scale
    /// multiplier: 1.0 at the default content size, larger as the user scales
    /// text up. Driven into the WebView's CSS so web text tracks the OS setting.
    private func dynamicTypeScale() -> CGFloat {
        let reference: CGFloat = 17
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: reference) / reference
    }

    private static func fontScaleScript(scale: CGFloat) -> String {
        "document.documentElement.style.setProperty('--font-scale', '\(String(format: "%.4f", scale))');"
    }

    private func applyFontScale() {
        webView?.evaluateJavaScript(
            Self.fontScaleScript(scale: dynamicTypeScale()),
            completionHandler: nil
        )
    }

    @objc private func contentSizeCategoryDidChange() {
        applyFontScale()
    }

    private func makeCloseButton() -> UIButton {
        let button = UIButton(type: .system)
        let symbol = UIImage(
            systemName: "xmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
                .applying(UIImage.SymbolConfiguration(hierarchicalColor: .secondaryLabel))
        )
        button.setImage(symbol, for: .normal)
        button.accessibilityLabel = "Close chat"
        button.addAction(
            UIAction { [weak self] _ in self?.dismiss(animated: true) },
            for: .touchUpInside
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8)
        ])
        return button
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            interactiveToolCompletions.failAll(with: .chatNotPresented)
            GradientChat.chatDismissed(self)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // The WKUserContentController outlives us via the configuration; drop
        // the handler so it doesn't deliver into a deallocated bridge.
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: WidgetBridge.handlerName
        )
    }
}

// MARK: - WKNavigationDelegate

extension ChatViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // On-origin navigations stay in the widget.
        if let origin = widgetOriginURL, ChatNavigationPolicy.isSameOrigin(url, as: origin) {
            decisionHandler(.allow)
            return
        }
        // Everything else goes to the system (browser, dialer, mail, …). We
        // never load off-origin content in this WebView, even if nothing can
        // open the URL. Strip the fragment first — widget URLs carry the user
        // JWT in the fragment and it must never leak to an external app.
        decisionHandler(.cancel)
        let external = ChatNavigationPolicy.strippingFragment(url)
        UIApplication.shared.open(external, options: [:], completionHandler: nil)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        reportMainFrameFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportMainFrameFailure(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        mainFrameLoadFailed = false
        fallbackCloseButton?.isHidden = true
        // The document-start seed uses the scale captured at viewDidLoad; re-apply
        // here so a reload after a text-size change lands on the current value.
        applyFontScale()
        redispatchPendingInteractiveToolCompletions()
        // Move VoiceOver into the chat once, on the first successful load, rather
        // than leaving focus on the presenting screen. Reloads keep their focus.
        if !didMoveVoiceOverFocus {
            didMoveVoiceOverFocus = true
            UIAccessibility.post(notification: .screenChanged, argument: webView)
        }
    }

    private func reportMainFrameFailure(_ error: Error) {
        let nsError = error as NSError
        // WebKit reports a cancelled load when we hand a navigation to the
        // system browser or the widget itself interrupts a load; neither
        // leaves the screen blank.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 {
            // WebKitErrorFrameLoadInterruptedByPolicyChange, from our own
            // decidePolicyFor .cancel.
            return
        }
        mainFrameLoadFailed = true
        interactiveToolCompletions.failAll(with: .widgetUnavailable)
        fallbackCloseButton?.isHidden = false
        // The widget never rendered, so there's nothing on screen for VoiceOver to
        // read and the only control is the fallback close button. Announce the
        // failure so the user isn't stranded in a silent modal.
        UIAccessibility.post(
            notification: .announcement,
            argument: "Couldn't load the chat. Use the close button to dismiss."
        )
        GradientChat.log.warning(
            "Widget load failed: \(nsError.code) \(nsError.localizedDescription, privacy: .public)"
        )
        GradientChat.dispatchUnavailable(.failedToLoad)
    }
}

// MARK: - UIScrollViewDelegate

extension ChatViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset != .zero {
            scrollView.contentOffset = .zero
        }
    }
}

// MARK: - WKUIDelegate

extension ChatViewController: WKUIDelegate {
    /// target=_blank links don't reach decidePolicyFor as a same-WebView
    /// navigation; open them externally instead of spawning a child WebView.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            let external = ChatNavigationPolicy.strippingFragment(url)
            UIApplication.shared.open(external, options: [:], completionHandler: nil)
        }
        return nil
    }
}
