import XCTest
@testable import AlpBrowser

// Pure-logic tests only: nothing here creates a window, a web view or touches the network.

final class PageModMatchingTests: XCTestCase {
    private func mod(_ domain: String) -> PageMod { PageMod(domain: domain) }

    func testExactHostMatches() {
        XCTAssertTrue(mod("x.com").matches(host: "x.com"))
    }

    func testSubdomainMatches() {
        XCTAssertTrue(mod("x.com").matches(host: "www.x.com"))
        XCTAssertTrue(mod("x.com").matches(host: "a.b.x.com"))
    }

    func testMatchingIgnoresCase() {
        XCTAssertTrue(mod("X.com").matches(host: "WWW.x.COM"))
    }

    func testSuffixLookalikeDoesNotMatch() {
        // The old substring match let a boost for x.com apply to box.com.
        XCTAssertFalse(mod("x.com").matches(host: "box.com"))
        XCTAssertFalse(mod("x.com").matches(host: "notx.com"))
    }

    func testDomainAsPrefixOrInfixDoesNotMatch() {
        XCTAssertFalse(mod("x.com").matches(host: "x.com.evil.org"))
        XCTAssertFalse(mod("x.com").matches(host: "evil.org"))
        XCTAssertFalse(mod("x.com").matches(host: ""))
    }

    func testSubdomainBoostDoesNotMatchParent() {
        XCTAssertFalse(mod("docs.x.com").matches(host: "x.com"))
        XCTAssertTrue(mod("docs.x.com").matches(host: "docs.x.com"))
    }
}

final class AdBlockRulesTests: XCTestCase {
    private func rules() throws -> [[String: Any]] {
        let json = try XCTUnwrap(AdBlockRules.json())
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(object as? [[String: Any]])
    }

    private func urlFilters(of type: String) throws -> [String] {
        try rules().compactMap { rule in
            guard (rule["action"] as? [String: Any])?["type"] as? String == type else { return nil }
            return (rule["trigger"] as? [String: Any])?["url-filter"] as? String
        }
    }

    func testOneBlockRulePerHostAndPattern() throws {
        let blocks = try urlFilters(of: "block")
        XCTAssertEqual(blocks.count, AdBlockRules.blockedThirdPartyHosts.count + AdBlockRules.blockedThirdPartyPatterns.count)
    }

    func testEveryRuleHasTriggerAndAction() throws {
        for rule in try rules() {
            XCTAssertNotNil((rule["trigger"] as? [String: Any])?["url-filter"])
            XCTAssertNotNil((rule["action"] as? [String: Any])?["type"])
        }
    }

    func testNoAlternationInFilters() throws {
        // WebKit content blockers reject `|` alternation, which silently disabled the old list.
        for filter in try urlFilters(of: "block") {
            XCTAssertFalse(filter.contains("|"), "alternation in \(filter)")
        }
    }

    func testFiltersCompileAsRegularExpressions() throws {
        for filter in try urlFilters(of: "block") {
            XCTAssertNoThrow(try NSRegularExpression(pattern: filter), filter)
        }
    }

    func testHostRulesMatchHostAndSubdomainsOnly() throws {
        let filter = try XCTUnwrap(try urlFilters(of: "block").first { $0.contains("doubleclick\\.net") })
        let regex = try NSRegularExpression(pattern: filter)
        func matches(_ url: String) -> Bool {
            regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
        XCTAssertTrue(matches("https://doubleclick.net/ad.js"))
        XCTAssertTrue(matches("https://ad.doubleclick.net/ad.js"))
        XCTAssertTrue(matches("https://static.ad.doubleclick.net:443/x"))
        XCTAssertFalse(matches("https://notdoubleclick.net/ad.js"))
        XCTAssertFalse(matches("https://doubleclick.net.example.org/ad.js"))
        XCTAssertFalse(matches("https://example.org/?u=doubleclick.net"))
    }

    func testBlockRulesAreThirdPartyOnly() throws {
        for rule in try rules() {
            guard (rule["action"] as? [String: Any])?["type"] as? String == "block" else { continue }
            let loadType = (rule["trigger"] as? [String: Any])?["load-type"] as? [String]
            XCTAssertEqual(loadType, ["third-party"])
        }
    }

    func testHidingRuleListsSelectors() throws {
        let hide = try XCTUnwrap(try rules().first {
            ($0["action"] as? [String: Any])?["type"] as? String == "css-display-none"
        })
        let selector = try XCTUnwrap((hide["action"] as? [String: Any])?["selector"] as? String)
        XCTAssertTrue(selector.contains(".adsbygoogle"))
    }

    func testHostListHasNoDuplicatesOrSchemes() {
        let hosts = AdBlockRules.blockedThirdPartyHosts
        XCTAssertEqual(Set(hosts).count, hosts.count)
        for host in hosts {
            XCTAssertFalse(host.contains("/") || host.contains(":"), host)
            XCTAssertEqual(host, host.lowercased())
        }
    }
}

final class FaviconParsingTests: XCTestCase {
    private let base = URL(string: "https://example.com/blog/")!

    func testFindsPlainIconAndResolvesRelativeURL() {
        let html = #"<html><head><link rel="stylesheet" href="/a.css"><link rel="icon" href="/img/f.png"></head>"#
        XCTAssertEqual(FaviconCache.iconURL(inHTML: html, baseURL: base)?.absoluteString, "https://example.com/img/f.png")
    }

    func testShortcutIconAndSingleQuotesAndAttributeOrder() {
        let html = "<LINK href='fav.png' REL='shortcut icon'>"
        XCTAssertEqual(FaviconCache.iconURL(inHTML: html, baseURL: base)?.absoluteString, "https://example.com/blog/fav.png")
    }

    func testPlainIconBeatsTouchIcon() {
        let html = #"<link rel="apple-touch-icon" href="/t.png"><link rel="icon" href="/i.png">"#
        XCTAssertEqual(FaviconCache.iconURL(inHTML: html, baseURL: base)?.path, "/i.png")
    }

    func testTouchIconUsedWhenNothingElse() {
        let html = #"<link rel="apple-touch-icon" href="/t.png">"#
        XCTAssertEqual(FaviconCache.iconURL(inHTML: html, baseURL: base)?.path, "/t.png")
    }

    func testSkipsSVGDataURIsAndMissingHref() {
        let html = #"<link rel="icon" href="/i.svg"><link rel="icon" href="data:image/png;base64,AAAA"><link rel="icon">"#
        XCTAssertNil(FaviconCache.iconURL(inHTML: html, baseURL: base))
    }

    func testNoLinkTags() {
        XCTAssertNil(FaviconCache.iconURL(inHTML: "<html><body>hi</body></html>", baseURL: base))
    }

    func testProbeableHosts() {
        XCTAssertTrue(FaviconCache.isProbeableHost("example.com"))
        XCTAssertFalse(FaviconCache.isProbeableHost("localhost"))
        XCTAssertFalse(FaviconCache.isProbeableHost("printer.local"))
        XCTAssertFalse(FaviconCache.isProbeableHost("192.168.1.10"))
        XCTAssertFalse(FaviconCache.isProbeableHost("::1"))
    }
}
