import Foundation
import WebKit
import AppKit
import Combine

@MainActor
public final class WebViewPool: NSObject, ObservableObject {
    public static let shared = WebViewPool()

    @Published public private(set) var liveWebViewCount: Int = 0
    @Published public private(set) var snapshots: [UUID: NSImage] = [:]
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

        let userContentController = WKUserContentController()
        if let ruleList = compiledContentRuleList, browserState?.adBlockerEnabled ?? true {
            userContentController.add(ruleList)
        }

        let coordinator = WebViewInstanceCoordinator(tabID: tab.id, pool: self)
        coordinators[tab.id] = coordinator
        userContentController.add(coordinator, name: "arcBridge")

        let bridgeJS = Self.arcBridgeUserScriptSource
        let bridgeScript = WKUserScript(source: bridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(bridgeScript)

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

    public func captureSnapshot(for tabID: UUID) async -> NSImage? {
        guard let wv = webViews[tabID] else { return snapshots[tabID] }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 720
        if let image = try? await wv.takeSnapshot(configuration: config) {
            snapshots[tabID] = image
            return image
        }
        return snapshots[tabID]
    }

    public func toggleMuteAudio(in tabID: UUID, muted: Bool) {
        guard let wv = webViews[tabID] else { return }
        let js = """
        document.querySelectorAll('video, audio').forEach(el => { el.muted = \(muted ? "true" : "false"); });
        """
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

    public func hibernateTab(id tabID: UUID) async {
        guard webViews[tabID] != nil else { return }
        _ = await captureSnapshot(for: tabID)
        destroyWebView(for: tabID)
    }

    public func destroyWebView(for tabID: UUID) {
        guard let wv = webViews.removeValue(forKey: tabID) else { return }
        wv.stopLoading()
        wv.configuration.userContentController.removeScriptMessageHandler(forName: "arcBridge")
        wv.configuration.userContentController.removeAllUserScripts()
        wv.navigationDelegate = nil
        wv.uiDelegate = nil
        wv.loadHTMLString("", baseURL: nil)
        coordinators.removeValue(forKey: tabID)
        liveWebViewCount = webViews.count
    }

    // MARK: - Boosts & Element Zapper

    public func applyBoost(_ boost: ArcBoost?, to tabID: UUID) {
        guard let wv = webViews[tabID] else { return }
        let css = (boost?.isEnabled == true) ? boost!.compiledCSS : ""
        let customJS = (boost?.isEnabled == true) ? boost!.customJS : ""

        let encodedCSS = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let js = """
        (function() {
            let styleEl = document.getElementById('arc-boost-live-style');
            if (!styleEl) {
                styleEl = document.createElement('style');
                styleEl.id = 'arc-boost-live-style';
                (document.head || document.documentElement).appendChild(styleEl);
            }
            styleEl.textContent = `\(encodedCSS)`;
        })();
        \(customJS)
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    public func setElementZapperActive(_ active: Bool, for tabID: UUID) {
        isZapperModeActive = active
        guard let wv = webViews[tabID] else { return }
        let js = "window.__arcSetZapperMode && window.__arcSetZapperMode(\(active ? "true" : "false"));"
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Find on Page & Arc Max Page Text Extraction

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

    // MARK: - Native Bytecode Ad/Tracker Blocker

    private func compileAdBlockerRules() {
        let rulesJSON = """
        [
            {
                "trigger": {
                    "url-filter": ".*",
                    "if-domain": ["*doubleclick.net", "*googlesyndication.com", "*google-analytics.com", "*googletagmanager.com", "*adnxs.com", "*taboola.com", "*outbrain.com", "*criteo.com", "*scorecardresearch.com", "*amazon-adsystem.com"]
                },
                "action": { "type": "block" }
            },
            {
                "trigger": {
                    "url-filter": "(doubleclick\\\\.net|googlesyndication\\\\.com|google-analytics\\\\.com|adservice\\\\.google\\\\.com|connect\\\\.facebook\\\\.net/en_US/fbevents\\\\.js|pagead2\\\\.googlesyndication\\\\.com)"
                },
                "action": { "type": "block" }
            }
        ]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "Arc2NativeAdBlocker",
            encodedContentRuleList: rulesJSON
        ) { [weak self] list, _ in
            guard let list = list else { return }
            Task { @MainActor in
                self?.compiledContentRuleList = list
            }
        }
    }

    // MARK: - Injected Bridge JS

    private static let arcBridgeUserScriptSource = """
    (function() {
        if (window.__arcBridgeInitialized) return;
        window.__arcBridgeInitialized = true;

        // 1. Shift+Click Link Interceptor for Arc Peek
        document.addEventListener('click', function(e) {
            if (window.__arcZapperActive) return;
            if (!e.shiftKey) return;
            const anchor = e.target.closest && e.target.closest('a[href]');
            if (anchor && anchor.href && anchor.href.startsWith('http')) {
                e.preventDefault();
                e.stopPropagation();
                window.webkit.messageHandlers.arcBridge.postMessage({
                    type: 'peekLink',
                    url: anchor.href,
                    title: (anchor.innerText || anchor.href).trim().slice(0, 120)
                });
            }
        }, true);

        // 2. Link Hover Status Bar Reporting (Arc Bottom Status Pill)
        let lastReportedHref = '';
        document.addEventListener('mouseover', function(e) {
            const anchor = e.target.closest && e.target.closest('a[href]');
            const href = (anchor && anchor.href && anchor.href.startsWith('http')) ? anchor.href : '';
            if (href !== lastReportedHref) {
                lastReportedHref = href;
                window.webkit.messageHandlers.arcBridge.postMessage({
                    type: 'hoverLink',
                    url: href
                });
            }
        }, { passive: true });

        // 3. Audio / Video Playback Reporting for Arc Sidebar Mini Player
        function notifyMediaState(playing) {
            window.webkit.messageHandlers.arcBridge.postMessage({
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

        // 4. Interactive Element Zapper for Arc Boosts
        let zapHoverOverlay = null;
        window.__arcZapperActive = false;

        function ensureOverlay() {
            if (zapHoverOverlay) return zapHoverOverlay;
            zapHoverOverlay = document.createElement('div');
            zapHoverOverlay.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #8B5CF6;background:rgba(139,92,246,0.18);border-radius:6px;transition:all 0.08s ease;display:none;box-shadow:0 0 16px rgba(139,92,246,0.45);';
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

        window.__arcSetZapperMode = function(active) {
            window.__arcZapperActive = !!active;
            const ov = ensureOverlay();
            if (!active) ov.style.display = 'none';
        };

        document.addEventListener('mousemove', function(e) {
            if (!window.__arcZapperActive) return;
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
            if (!window.__arcZapperActive) return;
            e.preventDefault();
            e.stopPropagation();
            const el = document.elementFromPoint(e.clientX, e.clientY);
            if (el && el !== document.body && el !== document.documentElement) {
                const selector = cssSelectorFor(el);
                el.style.setProperty('display', 'none', 'important');
                window.__arcSetZapperMode(false);
                window.webkit.messageHandlers.arcBridge.postMessage({
                    type: 'elementZapped',
                    selector: selector
                });
            }
        }, true);
    })();
    """
}

// MARK: - Per-Tab WKWebView Coordinator

@MainActor
final class WebViewInstanceCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
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
        pool?.browserState?.updateTabNavigationState(
            tabID: tabID,
            title: webView.title,
            urlString: webView.url?.absoluteString,
            isLoading: true,
            progress: max(webView.estimatedProgress, 0.15)
        )
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pool?.browserState?.updateTabNavigationState(
            tabID: tabID,
            title: webView.title,
            urlString: webView.url?.absoluteString,
            isLoading: true,
            progress: max(webView.estimatedProgress, 0.55)
        )
        if let host = webView.url?.host {
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let boost = pool?.browserState?.boost(forDomain: cleanHost)
            pool?.applyBoost(boost, to: tabID)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pool?.browserState?.updateTabNavigationState(
            tabID: tabID,
            title: webView.title,
            urlString: webView.url?.absoluteString,
            isLoading: false,
            progress: 1.0
        )
        if let host = webView.url?.host {
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let boost = pool?.browserState?.boost(forDomain: cleanHost)
            pool?.applyBoost(boost, to: tabID)
        }
        // Capture a background snapshot for the Control+Tab visual switcher
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            _ = await self.pool?.captureSnapshot(for: self.tabID)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pool?.browserState?.updateTabNavigationState(
            tabID: tabID,
            title: webView.title,
            urlString: webView.url?.absoluteString,
            isLoading: false,
            progress: 0
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let targetURL = navigationAction.request.url,
           let scheme = targetURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {

            if navigationAction.modifierFlags.contains(.shift) {
                decisionHandler(.cancel)
                pool?.browserState?.openPeek(
                    urlString: targetURL.absoluteString,
                    title: targetURL.host ?? targetURL.absoluteString,
                    sourceTabID: tabID
                )
                return
            }

            if navigationAction.modifierFlags.contains(.command) {
                decisionHandler(.cancel)
                pool?.browserState?.openNewTab(urlString: targetURL.absoluteString, inBackground: false)
                return
            }

            if let currentURL = webView.url?.absoluteString {
                pool?.recordNavigation(in: tabID, from: currentURL, to: targetURL.absoluteString)
            }
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let targetURL = navigationAction.request.url {
            if let sourceTab = pool?.browserState?.findTab(id: tabID),
               (sourceTab.isPinned || sourceTab.isFavorite) {
                pool?.browserState?.openPeek(
                    urlString: targetURL.absoluteString,
                    title: targetURL.host ?? targetURL.absoluteString,
                    sourceTabID: tabID
                )
            } else {
                pool?.browserState?.openNewTab(urlString: targetURL.absoluteString, inBackground: false)
            }
        }
        return nil
    }
}
