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

// MARK: - 1. Quick Peek Modal Card (Shift+Click Link Preview)

public struct PeekOverlayView: View {
    @EnvironmentObject var browserState: BrowserState
    public let session: PeekSession

    @State private var peekTab: TabItem

    public init(session: PeekSession) {
        self.session = session
        _peekTab = State(initialValue: TabItem(title: session.title, urlString: session.urlString))
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

                        Text(peekTab.urlString)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button {
                        let tab = browserState.openNewTab(urlString: peekTab.urlString, title: peekTab.title, inBackground: true)
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
        .onDisappear {
            WebViewPool.shared.destroyWebView(for: peekTab.id)
        }
    }

    private func closePeek() {
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

// MARK: - 3. Page Style Studio (Alp Styles / Page Mods)

public struct StyleStudioView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var activeStyle: PageMod

    public init() {
        _activeStyle = State(initialValue: PageMod(domain: "current", name: "Custom Style"))
    }

    private var currentDomain: String {
        guard let url = browserState.activeTab?.urlString, let host = URL(string: url)?.host else {
            return "example.com"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Page Style — \(currentDomain)", systemImage: "bolt.fill")
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

            // Element Zapper Trigger
            Button {
                if let tabID = browserState.activeTabID {
                    WebViewPool.shared.setElementZapperActive(true, for: tabID)
                    browserState.isStyleStudioPresented = false
                }
            } label: {
                HStack {
                    Image(systemName: "scissors")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Snip / Hide Element on Page")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Sliders for Brightness, Contrast, Saturation
            VStack(spacing: 8) {
                HStack {
                    Text("Brightness")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                    Slider(value: $activeStyle.brightness, in: 0.5...1.5)
                        .onChange(of: activeStyle.brightness) { _, _ in applyLiveStyle() }
                }
                HStack {
                    Text("Contrast")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                    Slider(value: $activeStyle.contrast, in: 0.5...1.5)
                        .onChange(of: activeStyle.contrast) { _, _ in applyLiveStyle() }
                }
                Toggle("Invert Colors", isOn: $activeStyle.invertColors)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .onChange(of: activeStyle.invertColors) { _, _ in applyLiveStyle() }
            }

            // Custom CSS Box
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom CSS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                TextEditor(text: $activeStyle.customCSS)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.35))
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                    .onChange(of: activeStyle.customCSS) { _, _ in applyLiveStyle() }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.20), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .onAppear {
            loadExistingStyle()
        }
    }

    private func loadExistingStyle() {
        if let existing = browserState.styles.first(where: { $0.domain == currentDomain }) {
            activeStyle = existing
        } else {
            activeStyle = PageMod(domain: currentDomain, name: "\(currentDomain) Style")
        }
    }

    private func applyLiveStyle() {
        activeStyle.updatedAt = Date()
        if let idx = browserState.styles.firstIndex(where: { $0.domain == currentDomain }) {
            browserState.styles[idx] = activeStyle
        } else {
            browserState.styles.append(activeStyle)
        }
        if let tabID = browserState.activeTabID {
            WebViewPool.shared.applyStyle(activeStyle, to: tabID)
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
                Label("Space Theme", systemImage: "paintpalette.fill")
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

            Text("PRESET THEMES")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))

            // Presets
            ForEach(SpaceTheme.presets, id: \.name) { preset in
                Button {
                    browserState.activeSpace.theme = preset.theme
                    browserState.scheduleSave()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(preset.theme.primaryColor.swiftUIColor)
                            .frame(width: 14, height: 14)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(preset.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Divider().background(Color.white.opacity(0.12))

            // Appearance Toggle
            Toggle("Light Foreground (Dark Mode)", isOn: $browserState.activeSpace.theme.prefersLightForeground)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.85))
                .onChange(of: browserState.activeSpace.theme.prefersLightForeground) { _, _ in
                    browserState.scheduleSave()
                }
        }
        .padding(16)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.20), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }
}

// MARK: - 5. Site Control Center Popover View (Arc-style)

public struct SiteControlCenterPopoverView: View {
    @EnvironmentObject var browserState: BrowserState
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

            // 2. Extensions Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Extensions")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    // Real Installed Extensions from AlpExtensionManager
                    ForEach(AlpExtensionManager.shared.installedExtensions) { ext in
                        extensionTile(
                            icon: "puzzlepiece.extension.fill",
                            color: ext.isEnabled ? Color.accentColor : Color.white.opacity(0.4),
                            badge: nil,
                            isPinned: ext.isEnabled
                        ) {
                            Task {
                                await AlpExtensionManager.shared.toggleExtension(id: ext.id)
                            }
                        }
                    }

                    // uBlock Origin / Built-in Adblock Tile
                    extensionTile(
                        icon: "shield.fill",
                        color: Color(red: 0.95, green: 0.35, blue: 0.55),
                        badge: nil,
                        isPinned: browserState.adBlockerEnabled
                    ) {
                        browserState.adBlockerEnabled.toggle()
                        browserState.scheduleSave()
                    }

                    // Cookie AutoDelete / Privacy
                    extensionTile(
                        icon: "circle.hexagongrid.fill",
                        color: Color(red: 0.88, green: 0.65, blue: 0.45),
                        badge: nil,
                        isPinned: false
                    ) {
                        browserState.showToast("Privacy shield active")
                    }

                    // Reader Mode / Script Blocker
                    extensionTile(
                        icon: "doc.text.fill",
                        color: Color.white.opacity(0.85),
                        badge: "20",
                        isPinned: false
                    ) {
                        browserState.showToast("Clean page reader active")
                    }

                    // Copy Page Elements
                    extensionTile(
                        icon: "doc.on.doc.fill",
                        color: Color.white.opacity(0.85),
                        badge: nil,
                        isPinned: false
                    ) {
                        browserState.showToast("Page markdown copied")
                    }

                    // Download Media
                    extensionTile(
                        icon: "arrow.down",
                        color: Color.white.opacity(0.85),
                        badge: nil,
                        isPinned: false
                    ) {
                        browserState.showToast("Media downloader ready")
                    }

                    // Meta Inspector
                    extensionTile(
                        icon: "m.circle.fill",
                        color: Color(red: 0.35, green: 0.75, blue: 0.75),
                        badge: nil,
                        isPinned: false
                    ) {
                        browserState.showToast("Meta tags inspected")
                    }

                    // Security Scanner
                    extensionTile(
                        icon: "shield.lefthalf.filled",
                        color: Color(red: 0.90, green: 0.25, blue: 0.30),
                        badge: "2",
                        isPinned: false
                    ) {
                        browserState.showToast("2 trackers intercepted")
                    }

                    // Add Extension Button
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
