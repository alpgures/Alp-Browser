//
//  WebViewPool.swift
//  Alp Browser
//
//  High-performance WKWebView pool with snapshot-based 0 MB RAM hibernation.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import WebKit
import AppKit
import Combine

@MainActor
public final class WebViewPool: NSObject, ObservableObject {
    public static let shared = WebViewPool()

    @Published public private(set) var liveWebViewCount: Int = 0
    @Published public var isZapperModeActive: Bool = false
    @Published public var hoveredLinkURL: String?

    private var webViews: [UUID: WKWebView] = [:]
    private var coordinators: [UUID: WebViewInstanceCoordinator] = [:]
    private var backHistoryStacks: [UUID: [String]] = [:]
    private var forwardHistoryStacks: [UUID: [String]] = [:]
    private var compiledContentRuleList: WKContentRuleList?

    public weak var browserState: BrowserState?

    private override init() {
        super.init()
        compileAdBlockerRules()
    }

    public func hasLiveWebView(for tabID: UUID) -> Bool {
        webViews[tabID] != nil
    }

    /// Ids of tabs that currently own a live WKWebView (everything else is hibernated or never loaded).
    public var liveTabIDs: [UUID] {
        Array(webViews.keys)
    }

    public func existingWebView(for tabID: UUID) -> WKWebView? {
        webViews[tabID]
    }

    public func canGoBack(in tabID: UUID) -> Bool {
        if let wv = webViews[tabID], wv.canGoBack {
            return true
        }
        return !(backHistoryStacks[tabID]?.isEmpty ?? true)
    }

    public func canGoForward(in tabID: UUID) -> Bool {
        if let wv = webViews[tabID], wv.canGoForward {
            return true
        }
        return !(forwardHistoryStacks[tabID]?.isEmpty ?? true)
    }

    public func webView(for tab: TabItem) -> WKWebView {
        if let existing = webViews[tab.id] {
            return existing
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 14.0, *) {
            config.preferences.isTextInteractionEnabled = true
        }
        if #available(macOS 15.4, *) {
            if let extController = AlpExtensionManager.shared.extensionController {
                config.webExtensionController = extController
            }
        }

        let userContentController = WKUserContentController()
        if let ruleList = compiledContentRuleList, browserState?.adBlockerEnabled ?? true {
            userContentController.add(ruleList)
        }

        let coordinator = WebViewInstanceCoordinator(tabID: tab.id, pool: self)
        coordinators[tab.id] = coordinator
        userContentController.add(coordinator, name: "alpBridge")

        installUserScripts(on: userContentController)

        config.userContentController = userContentController

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsMagnification = true
        wv.isInspectable = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

        webViews[tab.id] = wv
        liveWebViewCount = webViews.count

        if let url = URL(string: tab.urlString), url.scheme != nil {
            wv.load(URLRequest(url: url))
        }

        return wv
    }

    // MARK: - User Scripts (bridge + site boosts)

    /// (Re)installs every user script on a content controller: the bridge, then the enabled boosts.
    /// Boost CSS is injected at document start so styled pages never flash unstyled.
    private func installUserScripts(on ucc: WKUserContentController) {
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(
            source: Self.alpBridgeUserScriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        for script in Self.boostUserScripts(for: browserState?.styles ?? []) {
            ucc.addUserScript(script)
        }
    }

    /// Pushes the current boosts to every live tab's user scripts and restyles the pages already loaded.
    public func reapplyBoosts() {
        for (tabID, wv) in webViews {
            installUserScripts(on: wv.configuration.userContentController)
            guard let host = wv.url?.host else { continue }
            let match = browserState?.styles.first { $0.isEnabled && $0.matches(host: host) }
            applyStyle(match, to: tabID)
        }
    }

    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode([value]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    private static func hostMatchSnippet(domain: String) -> String {
        """
        var __alpHost = location.hostname.toLowerCase();
        var __alpDomain = \(jsStringLiteral(domain.lowercased()));
        if (__alpHost !== __alpDomain && !__alpHost.endsWith('.' + __alpDomain)) return;
        """
    }

    private static func boostUserScripts(for styles: [PageMod]) -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        for style in styles where style.isEnabled {
            let css = style.compiledCSS
            if !css.isEmpty {
                let source = """
                (function() {
                    \(hostMatchSnippet(domain: style.domain))
                    var el = document.createElement('style');
                    el.id = 'alp-page-mod-style';
                    el.textContent = \(jsStringLiteral(css));
                    function put() {
                        var parent = document.head || document.documentElement;
                        if (!parent) return false;
                        parent.appendChild(el);
                        return true;
                    }
                    if (!put()) document.addEventListener('DOMContentLoaded', put);
                })();
                """
                scripts.append(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
            let js = style.customJS.trimmingCharacters(in: .whitespacesAndNewlines)
            if !js.isEmpty {
                // Embedded directly (not eval'd) so strict page CSPs cannot block it; one script per
                // boost so a syntax error in one never disables the others.
                let source = """
                (function() {
                    \(hostMatchSnippet(domain: style.domain))
                    try {
                    \(js)
                    } catch (e) { console.error('Alp boost script error', e); }
                })();
                """
                scripts.append(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
        }
        return scripts
    }

    public func recordNavigation(in tabID: UUID, from oldURL: String?, to newURL: String) {
        guard let old = oldURL, !old.isEmpty, old != newURL else { return }
        var stack = backHistoryStacks[tabID] ?? []
        if stack.last != old {
            stack.append(old)
            backHistoryStacks[tabID] = stack
        }
        forwardHistoryStacks[tabID] = []
    }

    public func loadURL(_ urlString: String, in tabID: UUID) {
        guard let url = URL(string: urlString) else { return }
        if let wv = webViews[tabID] {
            if let current = wv.url?.absoluteString {
                recordNavigation(in: tabID, from: current, to: urlString)
            }
            wv.load(URLRequest(url: url))
        }
    }

    public func goBack(in tabID: UUID) {
        if let wv = webViews[tabID], wv.canGoBack {
            wv.goBack()
            return
        }
        if var backStack = backHistoryStacks[tabID], let previousURL = backStack.popLast() {
            backHistoryStacks[tabID] = backStack
            if let currentURL = webViews[tabID]?.url?.absoluteString ?? browserState?.findTab(id: tabID)?.urlString {
                var fwd = forwardHistoryStacks[tabID] ?? []
                fwd.append(currentURL)
                forwardHistoryStacks[tabID] = fwd
            }
            if let url = URL(string: previousURL) {
                webViews[tabID]?.load(URLRequest(url: url))
            }
        }
    }

    public func goForward(in tabID: UUID) {
        if let wv = webViews[tabID], wv.canGoForward {
            wv.goForward()
            return
        }
        if var fwdStack = forwardHistoryStacks[tabID], let nextURL = fwdStack.popLast() {
            forwardHistoryStacks[tabID] = fwdStack
            if let currentURL = webViews[tabID]?.url?.absoluteString ?? browserState?.findTab(id: tabID)?.urlString {
                var back = backHistoryStacks[tabID] ?? []
                back.append(currentURL)
                backHistoryStacks[tabID] = back
            }
            if let url = URL(string: nextURL) {
                webViews[tabID]?.load(URLRequest(url: url))
            }
        }
    }

    public func reload(in tabID: UUID) {
        if let wv = webViews[tabID] {
            if wv.url != nil {
                wv.reload()
            } else if let tab = browserState?.findTab(id: tabID), let url = URL(string: tab.urlString) {
                wv.load(URLRequest(url: url))
            }
        }
    }

    /// One-off page snapshot for the caller (screenshot-to-canvas / clipboard). Deliberately not
    /// cached: a retained bitmap per tab would defeat hibernation's "0 MB" goal.
    public func captureSnapshot(for tabID: UUID) async -> NSImage? {
        guard let wv = webViews[tabID] else { return nil }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 720
        return try? await wv.takeSnapshot(configuration: config)
    }

    public func toggleMuteAudio(in tabID: UUID, muted: Bool) {
        guard let wv = webViews[tabID] else { return }
        let js = "document.querySelectorAll('video, audio').forEach(el => { el.muted = \(muted ? "true" : "false"); });"
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    public func toggleMediaPlayback(in tabID: UUID) {
        guard let wv = webViews[tabID] else { return }
        let js = """
        document.querySelectorAll('video, audio').forEach(el => {
            if (el.paused) { el.play(); } else { el.pause(); }
        });
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Zero-RAM Tab Hibernation

    /// Releases the tab's WKWebView (and with it the web content process once nothing else shares it).
    /// Nothing is kept in memory for the tab: no snapshot, no view, no coordinator. Only the tab's
    /// URL and back/forward URL stacks (a few strings) remain, so selecting it reloads the page.
    public func hibernateTab(id tabID: UUID) {
        destroyWebView(for: tabID)
    }

    /// Forgets everything the pool keeps for a tab that is gone for good (closed, archived, deleted).
    public func forgetTab(_ tabID: UUID) {
        backHistoryStacks.removeValue(forKey: tabID)
        forwardHistoryStacks.removeValue(forKey: tabID)
    }

    public func destroyWebView(for tabID: UUID) {
        guard let wv = webViews.removeValue(forKey: tabID) else { return }
        let ucc = wv.configuration.userContentController
        wv.stopLoading()
        // The content controller retains its script message handler; break that link explicitly.
        ucc.removeScriptMessageHandler(forName: "alpBridge")
        ucc.removeAllUserScripts()
        ucc.removeAllContentRuleLists()
        wv.navigationDelegate = nil
        wv.uiDelegate = nil
        // A view still parented in a container would keep the web view alive.
        wv.removeFromSuperview()
        coordinators.removeValue(forKey: tabID)
        liveWebViewCount = webViews.count
        if isZapperModeActive { isZapperModeActive = false }
    }

    // MARK: - Page Styles & Element Zapper

    /// Live-updates the boost stylesheet on an open tab (CSS only; boost scripts run via
    /// `runBoostScript` or on the next load).
    public func applyStyle(_ style: PageMod?, to tabID: UUID) {
        guard let wv = webViews[tabID] else { return }
        let css = (style?.isEnabled == true) ? style!.compiledCSS : ""
        let js = """
        (function() {
            var styleEl = document.getElementById('alp-page-mod-style');
            if (!styleEl) {
                styleEl = document.createElement('style');
                styleEl.id = 'alp-page-mod-style';
                (document.head || document.documentElement).appendChild(styleEl);
            }
            styleEl.textContent = \(Self.jsStringLiteral(css));
        })();
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Runs a boost's custom script once on an open tab (the "Run" button in the Boost editor).
    public func runBoostScript(_ source: String, in tabID: UUID) {
        guard let wv = webViews[tabID] else { return }
        let wrapped = "(function(){ try {\n\(source)\n} catch (e) { console.error('Alp boost script error', e); } })();"
        wv.evaluateJavaScript(wrapped, completionHandler: nil)
    }

    public func setElementZapperActive(_ active: Bool, for tabID: UUID) {
        isZapperModeActive = active
        guard let wv = webViews[tabID] else { return }
        let js = "window.__alpSetZapperMode && window.__alpSetZapperMode(\(active ? "true" : "false"));"
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Find on Page

    public func findOnPage(query: String, forward: Bool = true, in tabID: UUID) {
        guard let wv = webViews[tabID], !query.isEmpty else { return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true
        wv.find(query, configuration: config) { _ in }
    }

    public func extractPageText(in tabID: UUID) async -> (title: String, url: String, content: String) {
        guard let wv = webViews[tabID] else {
            return ("", "", "")
        }
        let title = wv.title ?? ""
        let url = wv.url?.absoluteString ?? ""
        let js = "(document.body ? document.body.innerText : '').slice(0, 14000);"
        let text = (try? await wv.evaluateJavaScript(js) as? String) ?? ""
        return (title, url, text)
    }

    // MARK: - Ad & Tracker Blocker

    /// Bump the version suffix whenever the rule set changes; the compiled list is cached on disk by identifier.
    private static let adBlockRuleListID = "AlpBrowserNativeAdBlocker.v2"
    private static let legacyAdBlockRuleListIDs = ["AlpBrowserNativeAdBlocker"]

    private func compileAdBlockerRules() {
        let store = WKContentRuleListStore.default()
        for legacyID in Self.legacyAdBlockRuleListIDs {
            store?.removeContentRuleList(forIdentifier: legacyID) { _ in }
        }
        // Reuse the on-disk compiled list when present; compile (once per rule-set version) otherwise.
        store?.lookUpContentRuleList(forIdentifier: Self.adBlockRuleListID) { [weak self] existing, _ in
            if let existing = existing {
                Task { @MainActor in self?.adoptRuleList(existing) }
                return
            }
            guard let json = AdBlockRules.json() else { return }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: Self.adBlockRuleListID,
                encodedContentRuleList: json
            ) { list, error in
                if let error = error {
                    NSLog("Alp ad blocker rule compile failed: %@", String(describing: error))
                    return
                }
                guard let list = list else { return }
                Task { @MainActor in self?.adoptRuleList(list) }
            }
        }
    }

    private func adoptRuleList(_ list: WKContentRuleList) {
        compiledContentRuleList = list
        // Tabs created before compilation finished get the list now.
        guard browserState?.adBlockerEnabled ?? true else { return }
        for wv in webViews.values {
            wv.configuration.userContentController.add(list)
        }
    }

    /// Applies the Settings toggle to already-open tabs. Pages need a reload to pick up the change.
    public func setAdBlockerEnabled(_ enabled: Bool) {
        guard let list = compiledContentRuleList else { return }
        for wv in webViews.values {
            let ucc = wv.configuration.userContentController
            if enabled { ucc.add(list) } else { ucc.remove(list) }
        }
    }

    // MARK: - Injected Bridge Script

    private static let alpBridgeUserScriptSource = """
    (function() {
        if (window.__alpBridgeInitialized) return;
        window.__alpBridgeInitialized = true;

        // 1. Shift+Click Link Interceptor for Quick Peek
        document.addEventListener('click', function(e) {
            if (window.__alpZapperActive) return;
            if (!e.shiftKey) return;
            const anchor = e.target.closest && e.target.closest('a[href]');
            if (anchor && anchor.href && anchor.href.startsWith('http')) {
                e.preventDefault();
                e.stopPropagation();
                window.webkit.messageHandlers.alpBridge.postMessage({
                    type: 'peekLink',
                    url: anchor.href,
                    title: (anchor.innerText || anchor.href).trim().slice(0, 120)
                });
            }
        }, true);

        // 2. Link Hover Status Bar Reporting
        let lastReportedHref = '';
        document.addEventListener('mouseover', function(e) {
            const anchor = e.target.closest && e.target.closest('a[href]');
            const href = (anchor && anchor.href && anchor.href.startsWith('http')) ? anchor.href : '';
            if (href !== lastReportedHref) {
                lastReportedHref = href;
                window.webkit.messageHandlers.alpBridge.postMessage({
                    type: 'hoverLink',
                    url: href
                });
            }
        }, { passive: true });

        // 3. Audio / Video Playback Reporting for Sidebar Mini Player
        function notifyMediaState(playing) {
            window.webkit.messageHandlers.alpBridge.postMessage({
                type: 'mediaState',
                isPlaying: !!playing
            });
        }
        document.addEventListener('play', function(e) {
            if (e.target && (e.target.tagName === 'VIDEO' || e.target.tagName === 'AUDIO')) {
                notifyMediaState(true);
            }
        }, true);
        document.addEventListener('pause', function(e) {
            if (e.target && (e.target.tagName === 'VIDEO' || e.target.tagName === 'AUDIO')) {
                const anyPlaying = Array.from(document.querySelectorAll('video, audio')).some(el => !el.paused && !el.ended);
                notifyMediaState(anyPlaying);
            }
        }, true);

        // 4. Interactive Element Zapper for Page Styles
        let zapHoverOverlay = null;
        window.__alpZapperActive = false;

        function ensureOverlay() {
            if (zapHoverOverlay) return zapHoverOverlay;
            zapHoverOverlay = document.createElement('div');
            zapHoverOverlay.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #3B82F6;background:rgba(59,130,246,0.18);border-radius:6px;transition:all 0.08s ease;display:none;box-shadow:0 0 16px rgba(59,130,246,0.45);';
            document.documentElement.appendChild(zapHoverOverlay);
            return zapHoverOverlay;
        }

        function cssSelectorFor(el) {
            if (!el || el.nodeType !== 1) return '';
            if (el.id) return '#' + CSS.escape(el.id);
            if (el.className && typeof el.className === 'string') {
                const classes = el.className.trim().split(/\\s+/).filter(Boolean).slice(0, 2);
                if (classes.length > 0) {
                    return el.tagName.toLowerCase() + '.' + classes.map(c => CSS.escape(c)).join('.');
                }
            }
            return el.tagName.toLowerCase();
        }

        window.__alpSetZapperMode = function(active) {
            window.__alpZapperActive = !!active;
            const ov = ensureOverlay();
            if (!active) ov.style.display = 'none';
        };

        document.addEventListener('mousemove', function(e) {
            if (!window.__alpZapperActive) return;
            const el = document.elementFromPoint(e.clientX, e.clientY);
            if (!el || el === document.body || el === document.documentElement) return;
            const rect = el.getBoundingClientRect();
            const ov = ensureOverlay();
            ov.style.display = 'block';
            ov.style.left = rect.left + 'px';
            ov.style.top = rect.top + 'px';
            ov.style.width = rect.width + 'px';
            ov.style.height = rect.height + 'px';
        }, true);

        document.addEventListener('click', function(e) {
            if (!window.__alpZapperActive) return;
            e.preventDefault();
            e.stopPropagation();
            const el = document.elementFromPoint(e.clientX, e.clientY);
            if (el && el !== document.body && el !== document.documentElement) {
                const selector = cssSelectorFor(el);
                el.style.setProperty('display', 'none', 'important');
                window.__alpSetZapperMode(false);
                window.webkit.messageHandlers.alpBridge.postMessage({
                    type: 'elementZapped',
                    selector: selector
                });
            }
        }, true);
    })();
    """
}

// MARK: - Per-Tab Coordinator

@MainActor
final class WebViewInstanceCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let tabID: UUID
    weak var pool: WebViewPool?

    init(tabID: UUID, pool: WebViewPool) {
        self.tabID = tabID
        self.pool = pool
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "peekLink":
            if let url = body["url"] as? String {
                let title = (body["title"] as? String) ?? url
                pool?.browserState?.openPeek(urlString: url, title: title, sourceTabID: tabID)
            }
        case "hoverLink":
            let url = (body["url"] as? String) ?? ""
            let nextVal: String? = url.isEmpty ? nil : url
            if pool?.hoveredLinkURL != nextVal {
                pool?.hoveredLinkURL = nextVal
            }
        case "mediaState":
            let isPlaying = (body["isPlaying"] as? Bool) ?? false
            pool?.browserState?.mutateTab(id: tabID) { $0.isPlayingAudio = isPlaying }
        case "elementZapped":
            if let selector = body["selector"] as? String, !selector.isEmpty {
                pool?.isZapperModeActive = false
                pool?.browserState?.addZappedSelector(selector, forTabID: tabID)
            }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pool?.browserState?.mutateTab(id: tabID) { tab in
            tab.isLoading = true
            tab.estimatedProgress = 0.15
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pool?.browserState?.mutateTab(id: tabID) { tab in
            tab.estimatedProgress = 0.55
            if let current = webView.url?.absoluteString {
                tab.urlString = current
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let pageTitle = webView.title ?? ""
        let currentURL = webView.url?.absoluteString ?? ""

        pool?.browserState?.mutateTab(id: tabID) { tab in
            tab.isLoading = false
            tab.estimatedProgress = 1.0
            if !pageTitle.isEmpty {
                tab.title = pageTitle
            }
            if !currentURL.isEmpty {
                tab.urlString = currentURL
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pool?.browserState?.mutateTab(id: tabID) { tab in
            tab.isLoading = false
            tab.estimatedProgress = 0
        }
    }

    /// A failed or cancelled provisional navigation (DNS error, offline, user-cancelled) never reaches
    /// didFinish/didFail, which used to leave the progress bar stuck on screen.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pool?.browserState?.mutateTab(id: tabID) { tab in
            tab.isLoading = false
            tab.estimatedProgress = 0
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pool?.browserState?.mutateTab(id: tabID) { tab in
            tab.isLoading = false
            tab.estimatedProgress = 0
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let targetURL = navigationAction.request.url?.absoluteString {
            if navigationAction.modifierFlags.contains(.shift) {
                pool?.browserState?.openPeek(urlString: targetURL, title: targetURL, sourceTabID: tabID)
            } else {
                pool?.browserState?.openNewTab(urlString: targetURL, inBackground: false)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
        } else {
            decisionHandler(.allow, preferences)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        endLoadingState()
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        endLoadingState()
    }

    /// A navigation that turns into a download never reports didFinish, so clear the loading state here.
    private func endLoadingState() {
        pool?.browserState?.mutateTab(id: tabID) { tab in
            tab.isLoading = false
            tab.estimatedProgress = 0
        }
    }

    // MARK: - WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        var destURL = downloadsDir.appendingPathComponent(suggestedFilename)
        var counter = 1
        let baseName = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension

        while FileManager.default.fileExists(atPath: destURL.path) {
            let nextName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            destURL = downloadsDir.appendingPathComponent(nextName)
            counter += 1
        }

        pool?.browserState?.showToast("Downloading \(destURL.lastPathComponent)...")
        DownloadTracker.shared.begin(download, destination: destURL)
        completionHandler(destURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        DownloadTracker.shared.end(download)
        pool?.browserState?.showToast("Download completed to ~/Downloads")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        DownloadTracker.shared.end(download, failed: true)
        pool?.browserState?.showToast("Download failed: \(error.localizedDescription)")
    }
}
