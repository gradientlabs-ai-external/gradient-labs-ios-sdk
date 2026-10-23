# Gradient Chat SDK (iOS)

Embed Gradient Labs' AI chat in your iOS app. A zero-dependency Swift package
(iOS 15+) that hosts the chat in a WKWebView and exposes a small native API
(`boot`, `present`, listeners).

## See it working

Install the sample app from [TestFlight](https://testflight.apple.com/join/2ER3GRDP),
no build needed.

## Add it to your app

In Xcode: **File → Add Package Dependencies →**
`https://github.com/gradientlabs-ai-external/gradient-labs-ios-sdk` → pick a version.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/gradientlabs-ai-external/gradient-labs-ios-sdk", from: "0.6.2")
```

## Quick start

Your backend mints a short-lived HS256 JWT (5 minutes recommended), signed with
your widget secret. Its protected header contains `alg: HS256` and the widget
key as `kid`; its claims contain the user's ID as `sub` plus `iat` and `exp`.
The lifetime (`exp - iat`) must not exceed 1 hour. Find the widget key and
secret in `app.gradient-labs.ai/<company>/<branch>/workspace-settings/chat-sdk`.

```swift
GradientChat.boot(config: GradientChatConfig(widgetKey: "wpk_…", userJwt: backendJwt))
GradientChat.present(from: self)

// Re-mint when the session expires:
GradientChat.addListener(self)   // onAuthError → GradientChat.setUserJwt(...)
```

Call `GradientChat.logout()` on sign-out.

## Listener callbacks

`GradientChatListener` has three methods (all optional, all called on the main
thread). Register with `GradientChat.addListener(_:)`; listeners are held weakly,
so keep a strong reference.

```swift
// The session couldn't be established or expired. Mint a fresh JWT and pass it
// back via GradientChat.setUserJwt(...), respecting backoff for .rateLimited.
func onAuthError(_ error: GradientChatAuthError)          // .rateLimited, .sessionInvalid, .unknown(code:)

// A chat lifecycle event.
func onChatEvent(_ event: GradientChatEvent)              // .started(conversationId:internalId:), .handedOff,
                                                          // .messageReceived(messageId:sender:), .ended,
                                                          // .surveySubmitted(resolved:),
                                                          // .deeplinkRequested(requestID:url:)

// The chat can't be shown — hide the entry point or show your own fallback.
func onChatUnavailable(_ reason: GradientChatUnavailableReason)  // .notAvailable, .failedToLoad
```

For `.deeplinkRequested`, open the native flow and then call
`GradientChat.completeInteractiveTool(requestID:result:)` with its result.
