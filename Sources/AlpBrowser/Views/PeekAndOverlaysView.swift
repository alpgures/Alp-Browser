//
//  PeekAndOverlaysView.swift
//  Alp Browser
//
//  Clean-room overlays: Quick Peek, Find on Page, Style Studio, and Theme Picker.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import WebKit
import AppKit
import Combine

// MARK: - 1. Quick Peek Modal Card (Shift+Click Link Preview)

/// Mirrors the peek web view's load state. The peek tab is not part of the browser's tab list, so
/// the usual per-tab loading flags never reach it; this watches the web view directly.
final class PeekPageState: ObservableObject {
    @Published var title: String = ""
    @Published var urlString: String = ""
    @Published var progress: Double = 0
    @Published var isLoading: Bool = true

    private var observers: [AnyCancellable] = []

    func attach(_ webView: WKWebView) {
        observers.removeAll()
        observers = [
            webView.publisher(for: \.estimatedProgress).receive(on: DispatchQueue.main).sink { [weak self] in self?.progress = $0 },
            webView.publisher(for: \.isLoading).receive(on: DispatchQueue.main).sink { [weak self] in self?.isLoading = $0 },
            webView.publisher(for: \.title).receive(on: DispatchQueue.main).sink { [weak self] in self?.title = $0 ?? "" },
            webView.publisher(for: \.url).receive(on: DispatchQueue.main).sink { [weak self] in self?.urlString = $0?.absoluteString ?? "" }
        ]
    }

    /// Drops the KVO subscriptions so the web view is not kept alive by the overlay.
    func detach() {
        observers.removeAll()
    }
}

public struct PeekOverlayView: View {
    @EnvironmentObject var browserState: BrowserState
    public let session: PeekSession

    @State private var peekTab: TabItem
    @StateObject private var page = PeekPageState()

    public init(session: PeekSession) {
        self.session = session
        // The tab id is the session id, so BrowserState can find the live peek web view.
        _peekTab = State(initialValue: TabItem(id: session.id, title: session.title, urlString: session.urlString))
    }

    /// What the peek is showing now (it may have navigated since it opened).
    private var currentURLString: String {
        page.urlString.isEmpty ? peekTab.urlString : page.urlString
    }

    private var currentTitle: String {
        page.title.isEmpty ? peekTab.title : page.title
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    closePeek()
                }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(browserState.activeTheme.effectiveAccentColor)

                        Text("Quick Peek")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))

                        Text("•")
                            .foregroundStyle(.white.opacity(0.35))

                        Text(currentURLString)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button {
                        browserState.openPeekInNewWindow()
                    } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                            .font(.system(size: 11.5, weight: .semibold))
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open in New Window")

                    Button {
                        browserState.copyPeekLink()
                    } label: {
                        Label("Copy Link", systemImage: "link")
                            .font(.system(size: 11.5, weight: .semibold))
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy Link")

                    Button {
                        let tab = browserState.openNewTab(urlString: currentURLString, title: currentTitle, inBackground: true)
                        browserState.addSplitPane(withTabID: tab.id)
                        closePeek()
                    } label: {
                        Label("Split View", systemImage: "rectangle.split.2x1")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        browserState.expandPeekToFullTab()
                    } label: {
                        Label("Expand to Full Tab", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(browserState.activeTheme.primaryColor.swiftUIColor)
                    .controlSize(.small)

                    Button {
                        closePeek()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Close Peek (Esc)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.10, green: 0.10, blue: 0.13))
                .contextMenu {
                    Button("Open in New Window") { browserState.openPeekInNewWindow() }
                    Button("Copy Link") { browserState.copyPeekLink() }
                    Button("Expand to Full Tab") { browserState.expandPeekToFullTab() }
                }
                .overlay(alignment: .bottom) {
                    if page.isLoading && page.progress < 1.0 {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(browserState.activeTheme.effectiveAccentColor)
                                .frame(width: max(geo.size.width * CGFloat(page.progress), 24), height: 2)
                                .animation(.easeOut(duration: 0.2), value: page.progress)
                        }
                        .frame(height: 2)
                    }
                }

                WebViewRepresentable(tab: peekTab)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(6)
            }
            .frame(maxWidth: 960, maxHeight: 680)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 36, y: 16)
            .padding(36)
        }
        .onAppear {
            // webView(for:) is idempotent; the representable below gets the same instance.
            page.attach(WebViewPool.shared.webView(for: peekTab))
        }
        .onDisappear {
            page.detach()
            WebViewPool.shared.destroyWebView(for: peekTab.id)
            WebViewPool.shared.forgetTab(peekTab.id)
        }
    }

    private func closePeek() {
        page.detach()
        WebViewPool.shared.destroyWebView(for: peekTab.id)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            browserState.peekSession = nil
        }
    }
}

// MARK: - 2. Clean Find on Page Bar (⌘F)

public struct FindBarView: View {
    @EnvironmentObject var browserState: BrowserState
    @FocusState private var isFocused: Bool
    @State private var query: String = ""

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(browserState.activeTheme.primaryColor.swiftUIColor)

            TextField("Find in page...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .focused($isFocused)
                .frame(width: 180)
                .onSubmit {
                    if let tabID = browserState.activeTabID {
                        WebViewPool.shared.findOnPage(query: query, forward: true, in: tabID)
                    }
                }
                .onChange(of: query) { _, newValue in
                    if let tabID = browserState.activeTabID {
                        WebViewPool.shared.findOnPage(query: newValue, forward: true, in: tabID)
                    }
                }

            Button {
                if let tabID = browserState.activeTabID {
                    WebViewPool.shared.findOnPage(query: query, forward: false, in: tabID)
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Previous Match (⇧Enter)")

            Button {
                if let tabID = browserState.activeTabID {
                    WebViewPool.shared.findOnPage(query: query, forward: true, in: tabID)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Next Match (Enter)")

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    browserState.isFindBarPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
        )
        .shadow(radius: 12)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - 3. Boost Studio (per-site styles and scripts)

public struct StyleStudioView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var activeStyle: PageMod
    /// The last value written to the store; edits equal to it are not re-applied.
    @State private var lastApplied: PageMod

    public init() {
        let blank = PageMod(domain: "current", name: "Custom Boost")
        _activeStyle = State(initialValue: blank)
        _lastApplied = State(initialValue: blank)
    }

    private var activeWebHost: String? {
        guard let tab = browserState.activeTab, tab.kind == .web,
              let host = URL(string: tab.urlString)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var currentDomain: String { activeWebHost ?? "" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(activeWebHost.map { "Boost — \($0)" } ?? "Boost", systemImage: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        browserState.isStyleStudioPresented = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            if activeWebHost == nil {
                Text("Open a web page to create a boost for that site.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    editor
                }
                .frame(maxHeight: 480)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.20), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .onAppear { loadExistingStyle() }
        .onChange(of: activeStyle) { _, newValue in
            guard newValue != lastApplied else { return }
            applyLiveStyle()
        }
        .onDisappear {
            // Install the finished boost as a user script on open tabs and persist it.
            if browserState.styles.contains(where: { $0.domain == currentDomain }) {
                browserState.commitBoostChanges()
            }
        }
    }

    private var editor: some View {
        BoostEditorForm(
            boost: $activeStyle,
            enabledTitle: "Boost enabled on this site",
            pageActions: BoostPageActions(
                snipElement: {
                    if let tabID = browserState.activeTabID {
                        WebViewPool.shared.setElementZapperActive(true, for: tabID)
                        browserState.isStyleStudioPresented = false
                    }
                },
                runScript: { source in
                    if let tabID = browserState.activeTabID {
                        WebViewPool.shared.runBoostScript(source, in: tabID)
                    }
                }
            ),
            onReset: {
                let keepID = activeStyle.id
                var fresh = PageMod(domain: currentDomain, name: "\(currentDomain) Boost")
                fresh.id = keepID
                activeStyle = fresh
            },
            onDelete: {
                browserState.deleteBoost(id: activeStyle.id)
                browserState.isStyleStudioPresented = false
            }
        )
    }

    private func loadExistingStyle() {
        guard let domain = activeWebHost else { return }
        let loaded = browserState.styles.first(where: { $0.domain == domain })
            ?? PageMod(domain: domain, name: "\(domain) Boost")
        lastApplied = loaded
        activeStyle = loaded
    }

    /// Stores the edit and restyles the open page. User-script reinstall is deferred to dismissal so
    /// dragging a slider does not rebuild every tab's scripts on each tick.
    private func applyLiveStyle() {
        guard activeWebHost != nil else { return }
        var snapshot = activeStyle
        snapshot.updatedAt = Date()
        lastApplied = activeStyle
        if let idx = browserState.styles.firstIndex(where: { $0.id == snapshot.id }) {
            browserState.styles[idx] = snapshot
        } else {
            browserState.styles.append(snapshot)
        }
        if let tabID = browserState.activeTabID {
            WebViewPool.shared.applyStyle(snapshot, to: tabID)
        }
        browserState.scheduleSave()
    }
}

// MARK: - 4. Space Theme Picker

public struct SpaceThemePickerView: View {
    @EnvironmentObject var browserState: BrowserState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Space Theme Studio", systemImage: "paintpalette.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        browserState.isThemePickerPresented = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: false) {
                SpaceThemeStudioView()
            }
            .frame(maxHeight: 520)
        }
        .padding(18)
        .frame(width: 580)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.20), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }
}

// MARK: - 5. Site Control Center Popover View

public struct SiteControlCenterPopoverView: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var extensionManager = AlpExtensionManager.shared
    @State private var isDeveloperMode: Bool = false
    @State private var isPipAllowed: Bool = true

    public init() {}

    private var isHTTPS: Bool {
        browserState.activeTab?.urlString.hasPrefix("https://") == true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Top 4 Action Tiles (Share, Boost, Screenshot, Inspect)
            HStack(spacing: 8) {
                quickActionTile(icon: "square.and.arrow.up", label: "Share") {
                    if let url = browserState.activeTab?.urlString {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        browserState.showToast("Copied link to clipboard")
                    }
                    browserState.isSiteControlCenterPresented = false
                }

                quickActionTile(icon: "wand.and.stars", label: "Boost") {
                    browserState.isSiteControlCenterPresented = false
                    browserState.isStyleStudioPresented = true
                }

                quickActionTile(icon: "camera", label: "Capture") {
                    Task {
                        await browserState.capturePageToCanvasOrClipboard(sendToCanvas: true)
                    }
                    browserState.isSiteControlCenterPresented = false
                }

                quickActionTile(icon: "viewfinder", label: "Crop") {
                    Task {
                        await browserState.capturePageToCanvasOrClipboard(sendToCanvas: false)
                    }
                    browserState.isSiteControlCenterPresented = false
                }
            }

            // 2. Extensions Section (including imported extensions)
            VStack(alignment: .leading, spacing: 8) {
                Text("Extensions")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Array(extensionManager.installedExtensions.enumerated()), id: \.element.id) { idx, ext in
                        Button {
                            Task {
                                await extensionManager.toggleExtension(id: ext.id)
                            }
                            browserState.showToast("\(ext.name) \(ext.isEnabled ? "disabled" : "enabled")")
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(ext.isEnabled ? 0.10 : 0.04))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Group {
                                            if let nsImg = ext.iconImage {
                                                Image(nsImage: nsImg)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 22, height: 22)
                                                    .opacity(ext.isEnabled ? 1.0 : 0.4)
                                            } else {
                                                Image(systemName: "puzzlepiece.extension.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(ext.isEnabled ? Color.accentColor : Color.white.opacity(0.4))
                                            }
                                        }
                                    )

                                if idx == 0 && ext.isEnabled {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 7.5, weight: .bold))
                                        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.17))
                                        .padding(3.5)
                                        .background(Circle().fill(Color.white))
                                        .offset(x: 2, y: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("\(ext.name) (v\(ext.version))")
                    }

                    // Add / Manage Extensions Button
                    Button {
                        browserState.isSiteControlCenterPresented = false
                        browserState.isSettingsPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 48, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Manage Extensions")
                }
            }

            // 3. Settings Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                // Developer Mode Row
                Button {
                    isDeveloperMode.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "hammer.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Developer Mode")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(isDeveloperMode ? "On" : "Off")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)

                // Automatic Picture-In-Picture Row
                Button {
                    isPipAllowed.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.18))
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Automatic Picture-In-P...")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(isPipAllowed ? "Allowed" : "Blocked")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }

            // 4. Bottom Bar: Secure Badge and More Options
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: isHTTPS ? "lock.fill" : "lock.slash.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isHTTPS ? .white : Color.orange)
                    Text(isHTTPS ? "Secure" : "Not Secure")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                )

                Spacer()

                Button {
                    browserState.isSiteControlCenterPresented = false
                    browserState.isSettingsPresented = true
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "ellipsis")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }
                .buttonStyle(.plain)
                .help("More Site Settings")
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.12, green: 0.14, blue: 0.17).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 26, y: 12)
    }

    @ViewBuilder
    private func quickActionTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 52, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    private func extensionTile(
        icon: String,
        color: Color,
        badge: String?,
        isPinned: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(color)
                    )

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(Color.white.opacity(0.35)))
                        .offset(x: 2, y: 2)
                } else if let b = badge {
                    Text(b)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                        .offset(x: 2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 6. Visual Tab Switcher (Control + Tab)

public struct VisualTabSwitcherOverlayView: View {
    @EnvironmentObject var browserState: BrowserState

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("SWITCH TAB")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(0.6)

                HStack(spacing: 12) {
                    ForEach(Array(browserState.switcherCandidateTabs.enumerated()), id: \.element.id) { index, tab in
                        let isSelected = (index == browserState.tabSwitcherSelectedIndex)
                        VStack(spacing: 8) {
                            if let fav = FaviconCache.shared.favicon(for: tab.urlString) {
                                Image(nsImage: fav)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)
                            }

                            Text(tab.displayTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(width: 90)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? browserState.activeTheme.primaryColor.swiftUIColor : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(isSelected ? 0.8 : 0.12), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
            )
            .shadow(radius: 28)
        }
    }
}
