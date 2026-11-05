//
//  AdBlockRules.swift
//  Alp Browser
//
//  Pure generator for the WKContentRuleList JSON used by the ad and tracker blocker.
//  Kept free of UI and actor state so it can be unit tested.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation

enum AdBlockRules {
    /// Third-party ad, tracking and pop-under network hosts. Each becomes one rule that matches the
    /// host and any subdomain, only when loaded as a third-party resource (so visiting the site
    /// itself still works).
    static let blockedThirdPartyHosts: [String] = [
        // Ad exchanges, SSPs and DSPs
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagservices.com",
        "adservice.google.com", "2mdn.net", "adnxs.com", "adsrvr.org", "advertising.com", "adform.net",
        "adroll.com", "amazon-adsystem.com", "criteo.com", "criteo.net", "casalemedia.com", "indexww.com",
        "openx.net", "pubmatic.com", "rubiconproject.com", "smartadserver.com", "bidswitch.net",
        "contextweb.com", "lijit.com", "sovrn.com", "triplelift.com", "gumgum.com", "spotxchange.com",
        "springserve.com", "serving-sys.com", "zedo.com", "adition.com", "appnexus.com", "adcolony.com",
        "applovin.com", "yieldmo.com", "sharethrough.com", "teads.tv", "33across.com", "media.net",
        "tremorhub.com", "mathtag.com", "turn.com", "bttrack.com", "adsymptotic.com", "adtechus.com",
        "advertising.amazon.com", "ads.yahoo.com", "adsafeprotected.com", "moatads.com", "doubleverify.com",
        // Native / recommendation widgets
        "taboola.com", "outbrain.com", "revcontent.com", "mgid.com", "zemanta.com", "nativeads.com",
        // Measurement, audience and tracking pixels
        "google-analytics.com", "googletagmanager.com", "scorecardresearch.com", "quantserve.com",
        "quantcount.com", "chartbeat.net", "bluekai.com", "krxd.net", "demdex.net", "everesttech.net",
        "omtrdc.net", "2o7.net", "agkn.com", "rlcdn.com", "tapad.com", "liadm.com", "exelator.com",
        "pippio.com", "hotjar.com", "mouseflow.com", "fullstory.com", "crazyegg.com", "clarity.ms",
        "bat.bing.com",
        // Social-network ad and tracking endpoints
        "ads-twitter.com", "analytics.twitter.com", "ads.linkedin.com", "px.ads.linkedin.com",
        "snap.licdn.com", "analytics.tiktok.com", "ads.tiktok.com", "ads.pinterest.com", "ct.pinterest.com",
        "alb.reddit.com", "events.redditmedia.com", "sc-static.net", "tr.snapchat.com",
        // Pop-up / pop-under networks
        "popads.net", "popcash.net", "propellerads.com", "onclickads.net", "exoclick.com", "juicyads.com",
        "trafficjunky.net", "adsterra.com", "hilltopads.net", "clickadu.com", "ad-maven.com", "adcash.com"
    ]

    /// Third-party URL patterns that identify ad or tracking scripts on otherwise unknown hosts.
    /// WebKit content-blocker regexes do not support alternation, so each pattern is its own rule.
    static let blockedThirdPartyPatterns: [String] = [
        "/pagead/",
        "/adsbygoogle\\.js",
        "/prebid[0-9a-z._-]*\\.js",
        "/fbevents\\.js",
        "facebook\\.com/tr[/?]",
        "/ads/ga-audiences"
    ]

    /// Selectors for ad containers left behind when their scripts are blocked.
    static let hiddenAdSelectors: [String] = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_iframe\"]", "[id^=\"div-gpt-ad\"]",
        "[data-google-query-id]", "[data-ad-slot]", ".ad-banner", ".ad-container", ".advertisement",
        ".advert", ".sponsored-ad", "[id^=\"taboola-\"]", ".OUTBRAIN", "[id^=\"outbrain\"]",
        "iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"googlesyndication.com\"]"
    ]

    static func json() -> String? {
        let blockAction: [String: Any] = ["type": "block"]
        var rules: [[String: Any]] = []
        for host in blockedThirdPartyHosts {
            let escaped = host.replacingOccurrences(of: ".", with: "\\.")
            let trigger: [String: Any] = [
                "url-filter": "^[^:]+://+([^:/]+\\.)?\(escaped)[:/]",
                "load-type": ["third-party"]
            ]
            rules.append(["trigger": trigger, "action": blockAction])
        }
        for pattern in blockedThirdPartyPatterns {
            let trigger: [String: Any] = ["url-filter": pattern, "load-type": ["third-party"]]
            rules.append(["trigger": trigger, "action": blockAction])
        }
        let hideTrigger: [String: Any] = ["url-filter": ".*"]
        let hideAction: [String: Any] = [
            "type": "css-display-none",
            "selector": hiddenAdSelectors.joined(separator: ", ")
        ]
        rules.append(["trigger": hideTrigger, "action": hideAction])
        guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
