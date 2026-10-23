import XCTest
@testable import GradientChat

final class WidgetURLTests: XCTestCase {
    func testLoadURLCarriesJwtInFragment() {
        let url = WidgetURL.load(
            origin: "https://chat-sdk-widget.vercel.app",
            jwt: "abc.def.ghi",
            conversationToken: nil,
            tags: [],
            shortSession: false
        )
        XCTAssertEqual(url?.absoluteString, "https://chat-sdk-widget.vercel.app/#jwt=abc.def.ghi")
    }

    func testLoadURLAppendsShortSessionFlag() {
        let url = WidgetURL.load(
            origin: "http://localhost:5173",
            jwt: "abc.def.ghi",
            conversationToken: nil,
            tags: [],
            shortSession: true
        )
        XCTAssertEqual(
            url?.absoluteString,
            "http://localhost:5173/#jwt=abc.def.ghi&use_short_session=1"
        )
    }

    func testFragmentMatchesLoadURL() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: nil, tags: [], shortSession: false),
            "#jwt=j"
        )
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: nil, tags: [], shortSession: true),
            "#jwt=j&use_short_session=1"
        )
    }

    func testNilConversationTokenIsOmitted() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: nil, tags: [], shortSession: false),
            "#jwt=j"
        )
    }

    func testEmptyConversationTokenIsOmitted() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: "", tags: [], shortSession: false),
            "#jwt=j"
        )
    }

    func testConversationTokenIsPercentEncoded() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: "a b&c", tags: [], shortSession: false),
            "#jwt=j&conversation_token=a%20b%26c"
        )
    }

    func testConversationTokenPrecedesShortSessionFlag() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: "tok", tags: [], shortSession: true),
            "#jwt=j&conversation_token=tok&use_short_session=1"
        )
    }

    func testNoTagsAddsNoTagParam() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: nil, tags: [], shortSession: false),
            "#jwt=j"
        )
    }

    func testEachTagAddsOneRepeatedParamInOrder() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: "tok", tags: ["vip", "billing"], shortSession: true),
            "#jwt=j&conversation_token=tok&tag=vip&tag=billing&use_short_session=1"
        )
    }

    func testTagIsPercentEncoded() {
        XCTAssertEqual(
            WidgetURL.fragment(jwt: "j", conversationToken: nil, tags: ["a b&c=d+e#f"], shortSession: false),
            "#jwt=j&tag=a%20b%26c%3Dd%2Be%23f"
        )
    }

    func testLoadURLCarriesTags() {
        let url = WidgetURL.load(
            origin: "https://chat-sdk-widget.vercel.app",
            jwt: "abc.def.ghi",
            conversationToken: nil,
            tags: ["vip"],
            shortSession: false
        )
        XCTAssertEqual(url?.absoluteString, "https://chat-sdk-widget.vercel.app/#jwt=abc.def.ghi&tag=vip")
    }

    func testJsStringEscapesQuoteBreakouts() {
        XCTAssertEqual(WidgetURL.jsString("plain"), "'plain'")
        XCTAssertEqual(WidgetURL.jsString("a'b"), "'a\\'b'")
        XCTAssertEqual(WidgetURL.jsString("a\\b"), "'a\\\\b'")
        XCTAssertEqual(WidgetURL.jsString("a\nb"), "'a\\nb'")
        XCTAssertEqual(WidgetURL.jsString("a\rb"), "'a\\rb'")
    }
}
