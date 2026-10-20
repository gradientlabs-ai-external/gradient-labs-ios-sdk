import XCTest
@testable import GradientChat

final class WidgetURLTests: XCTestCase {
    func testLoadURLCarriesJwtInFragment() {
        let url = WidgetURL.load(
            origin: "https://chat-sdk-widget.vercel.app",
            jwt: "abc.def.ghi",
            conversationToken: nil,
            shortSession: false
        )
        XCTAssertEqual(url?.absoluteString, "https://chat-sdk-widget.vercel.app/#jwt=abc.def.ghi")
    }

    func testLoadURLAppendsShortSessionFlag() {
        let url = WidgetURL.load(
            origin: "http://localhost:5173",
            jwt: "abc.def.ghi",
            conversationToken: nil,
            shortSession: true
        )
        XCTAssertEqual(
            url?.absoluteString,
            "http://localhost:5173/#jwt=abc.def.ghi&use_short_session=1"
        )
    }

    func testFragmentMatchesLoadURL() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: nil, shortSession: false),
            "#jwt=j"
        )
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: nil, shortSession: true),
            "#jwt=j&use_short_session=1"
        )
    }

    func testNilConversationTokenIsOmitted() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: nil, shortSession: false),
            "#jwt=j"
        )
    }

    func testEmptyConversationTokenIsOmitted() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: "", shortSession: false),
            "#jwt=j"
        )
    }

    func testConversationTokenIsPercentEncoded() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: "a b&c", shortSession: false),
            "#jwt=j&conversation_token=a%20b%26c"
        )
    }

    func testConversationTokenPrecedesShortSessionFlag() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: "tok", shortSession: true),
            "#jwt=j&conversation_token=tok&use_short_session=1"
        )
    }

    func testJsStringEscapesQuoteBreakouts() {
        XCTAssertEqual(WidgetURL.jsString("plain"), "'plain'")
        XCTAssertEqual(WidgetURL.jsString("a'b"), "'a\\'b'")
        XCTAssertEqual(WidgetURL.jsString("a\\b"), "'a\\\\b'")
        XCTAssertEqual(WidgetURL.jsString("a\nb"), "'a\\nb'")
        XCTAssertEqual(WidgetURL.jsString("a\rb"), "'a\\rb'")
    }
}
