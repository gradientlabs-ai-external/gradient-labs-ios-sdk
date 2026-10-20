import XCTest
@testable import GradientChat

final class NavigationPolicyTests: XCTestCase {
    private let prodOrigin = URL(string: "https://chat-sdk-widget.vercel.app")!
    private let localOrigin = URL(string: "http://localhost:5173")!

    func testBareOriginIsSameOrigin() {
        XCTAssertTrue(
            ChatNavigationPolicy.isSameOrigin(
                URL(string: "https://chat-sdk-widget.vercel.app")!,
                as: prodOrigin
            )
        )
    }

    func testPathOnSameHostIsSameOrigin() {
        XCTAssertTrue(
            ChatNavigationPolicy.isSameOrigin(
                URL(string: "https://chat-sdk-widget.vercel.app/some/path?q=1#frag")!,
                as: prodOrigin
            )
        )
    }

    func testExplicitDefaultPortIsSameOrigin() {
        XCTAssertTrue(
            ChatNavigationPolicy.isSameOrigin(
                URL(string: "https://chat-sdk-widget.vercel.app:443/")!,
                as: prodOrigin
            )
        )
    }

    func testHostComparisonIsCaseInsensitive() {
        XCTAssertTrue(
            ChatNavigationPolicy.isSameOrigin(
                URL(string: "HTTPS://CHAT-SDK-WIDGET.VERCEL.APP/")!,
                as: prodOrigin
            )
        )
    }

    func testDifferentHostIsOffOrigin() {
        XCTAssertFalse(
            ChatNavigationPolicy.isSameOrigin(URL(string: "https://example.com/")!, as: prodOrigin)
        )
    }

    func testDifferentSchemeIsOffOrigin() {
        XCTAssertFalse(
            ChatNavigationPolicy.isSameOrigin(
                URL(string: "http://chat-sdk-widget.vercel.app/")!,
                as: prodOrigin
            )
        )
    }

    func testDifferentPortIsOffOrigin() {
        XCTAssertFalse(
            ChatNavigationPolicy.isSameOrigin(URL(string: "http://localhost:4000/")!, as: localOrigin)
        )
    }

    func testNonHttpSchemeIsOffOrigin() {
        XCTAssertFalse(
            ChatNavigationPolicy.isSameOrigin(URL(string: "mailto:help@example.com")!, as: prodOrigin)
        )
    }

    func testStrippingFragmentRemovesJwt() {
        let url = URL(string: "https://example.com/page?q=1#jwt=secret.token.here")!
        XCTAssertEqual(
            ChatNavigationPolicy.strippingFragment(url).absoluteString,
            "https://example.com/page?q=1"
        )
    }

    func testStrippingFragmentLeavesFragmentlessURLAlone() {
        let url = URL(string: "https://example.com/page?q=1")!
        XCTAssertEqual(ChatNavigationPolicy.strippingFragment(url), url)
    }
}
