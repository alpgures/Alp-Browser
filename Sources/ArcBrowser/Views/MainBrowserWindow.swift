import SwiftUI
import WebKit
import AppKit

public struct MainBrowserWindow: View {
    @EnvironmentObject var browserState: BrowserState

    public init() {}

    public var body: some View {
        ZStack {
            // 1. Arc Space Gradient + Vibrancy + Grain Backdrop
            ArcSpaceBackgroundView(theme: browserState.activeTheme)
                .ignoresSafeArea()

            // 2. Main Split Layout (Sidebar + Inset Rounded Web Viewport)
            HStack(spacing: 0) {
                if !browserState.isSidebarCollapsed {
                    SidebarView()
                        .frame(width: browserState.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    SidebarResizeHandle(sidebarWidth: $browserState.sidebarWidth)
                }

                // Main Rounded Web Viewport (Single or Split View)
                viewportArea
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                    .padding(.leading, browserState.isSidebarCollapsed ? 8 : 2)
            }

            // 3. Collapsed Sidebar Left-Edge Hover Trigger + Floating Sidebar Overlay
            if browserState.isSidebarCollapsed {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 10)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                                    browserState.isSidebarHoverPeeking = true
                                }
                            }
                        }
                    Spacer()
                }

                if browserState.isSidebarHoverPeeking {
                    HStack(spacing: 0) {
                        SidebarView()
                            .frame(width: browserState.sidebarWidth)
                            .background(
                                ArcSpaceBackgroundView(theme: browserState.activeTheme)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.45), radius: 26, x: 8, y: 8)
                            .padding(.leading, 8)
                            .padding(.vertical, 8)
                            .onHover { stillInside in
                                if !stillInside {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                                        browserState.isSidebarHoverPeeking = false
                                    }
                                }
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        Spacer()
                    }
                }
            }

            // 4. Floating Overlays (Site Control Center, Theme Picker, Find & Ask Bar, Boost Studio)
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        if browserState.isSiteControlCenterPresented {
                            SiteControlCenterPopoverView()
                                .padding(.leading, 14)
                                .padding(.top, 78)
                                .transition(.scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity))
                        }

                        if browserState.isThemePickerPresented {
                            SpaceThemePickerView()
                                .padding(.leading, browserState.isSidebarCollapsed ? 18 : max(18, browserState.sidebarWidth - 16))
                                .padding(.top, 44)
                                .transition(.scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        if browserState.isFindAndAskBarPresented {
                            FindAndAskBarView()
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if browserState.isBoostStudioPresented {
                            BoostStudioView()
                                .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 20)
                }
                Spacer()
            }

            // 5. Arc Peek Modal Sheet (Shift+Click Link Preview)
            if let peek = browserState.peekSession {
                PeekOverlayView(session: peek)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // 6. Control + Tab Visual Recent Tab Switcher
            if browserState.isTabSwitcherPresented {
                VisualTabSwitcherOverlayView()
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // 7. Floating Arc Command Bar (⌘T / ⌘L)
            if browserState.isCommandBarPresented {
                CommandBarView()
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            // 8. Bottom-Right Toast Notification Pill
            if let toast = browserState.toastMessage {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(browserState.activeTheme.effectiveAccentColor)
                            Text(toast)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.08, green: 0.08, blue: 0.11).opacity(0.92))
                                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                        )
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        .padding(.trailing, 22)
                        .padding(.bottom, 22)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $browserState.isLibrarySheetPresented) {
            LibrarySheetView()
                .environmentObject(browserState)
        }
    }

    // MARK: - Viewport Area (Single Tab or Multi-Pane Split View)

    @ViewBuilder
    private var viewportArea: some View {
        let visibleIDs = browserState.visibleViewportTabIDs
        let tabs = visibleIDs.compactMap { browserState.findTab(id: $0) }

        if tabs.count > 1 {
            if browserState.activeSpace.splitOrientation == .horizontal {
                HStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        ViewportPaneView(
                            tab: tab,
                            isSplitMode: true,
                            isFocusedPane: browserState.activeTabID == tab.id
                        )
                    }
                }
                .shadow(color: .black.opacity(0.22), radius: 10, y: 2)
            } else {
                VStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        ViewportPaneView(
                            tab: tab,
                            isSplitMode: true,
                            isFocusedPane: browserState.activeTabID == tab.id
                        )
                    }
                }
                .shadow(color: .black.opacity(0.22), radius: 10, y: 2)
            }
        } else if let singleTab = tabs.first ?? browserState.activeTab {
            ViewportPaneView(
                tab: singleTab,
                isSplitMode: false,
                isFocusedPane: true
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 2)
        } else {
            emptyStateViewport
        }
    }

    private var emptyStateViewport: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))

            VStack(spacing: 14) {
                Text(browserState.activeSpace.iconEmoji)
                    .font(.system(size: 46))

                Text(browserState.activeSpace.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Press ⌘T to open the Command Bar or select any tab in the sidebar.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        browserState.openCommandBar()
                    } label: {
                        Label("Command Bar (⌘T)", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(browserState.activeTheme.primaryColor.swiftUIColor)

                    Button {
                        browserState.createNewEasel(title: "\(browserState.activeSpace.title) Board")
                    } label: {
                        Label("New Easel", systemImage: "scribble.variable")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Control + Tab Visual Recent Tab Switcher Overlay

struct VisualTabSwitcherOverlayView: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject var webViewPool = WebViewPool.shared

    var body: some View {
        let candidates = browserState.switcherCandidateTabs
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    browserState.isTabSwitcherPresented = false
                }

            HStack(spacing: 14) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, tab in
                    let isSelected = idx == browserState.tabSwitcherSelectedIndex
                    Button {
                        browserState.tabSwitcherSelectedIndex = idx
                        browserState.commitTabSwitcherSelection()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .windowBackgroundColor))

                                if let snap = webViewPool.snapshots[tab.id] {
                                    Image(nsImage: snap)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 190, height: 124)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else {
                                    FaviconBadgeView(tab: tab, size: 36)
                                }
                            }
                            .frame(width: 190, height: 124)

                            HStack(spacing: 6) {
                                FaviconBadgeView(tab: tab, size: 15)
                                Text(tab.displayTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? browserState.activeTheme.primaryColor.swiftUIColor.opacity(0.65) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Color.white : Color.white.opacity(0.16), lineWidth: isSelected ? 2.0 : 0.8)
                        )
                        .scaleEffect(isSelected ? 1.04 : 0.97)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.11).opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.22), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.55), radius: 34, y: 14)
        }
    }
}

// MARK: - Arc Site Control Center Popover (URL Pill Lock/Tune Menu)

struct SiteControlCenterPopoverView: View {
    @EnvironmentObject var browserState: BrowserState

    private var activeTab: TabItem? {
        browserState.activeTab
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: activeTab?.urlString.hasPrefix("https") == true ? "lock.shield.fill" : "globe")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeTab?.simplifiedDomain ?? "Site Controls")
                        .font(.system(size: 13, weight: .bold))
                    Text(activeTab?.urlString.hasPrefix("https") == true ? "Encrypted HTTPS Connection" : "Standard Connection")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    browserState.isSiteControlCenterPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Toggle("Native Content & Tracker Blocker", isOn: $browserState.adBlockerEnabled)
                .font(.system(size: 12, weight: .medium))

            Button {
                browserState.isSiteControlCenterPresented = false
                browserState.isBoostStudioPresented = true
            } label: {
                Label("Customize Site with Arc Boost...", systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                browserState.isSiteControlCenterPresented = false
                Task {
                    await browserState.capturePageToEaselOrClipboard(sendToEasel: true)
                }
            } label: {
                Label("Capture Page to Easel & Clipboard (⌘⇧2)", systemImage: "camera.viewfinder")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                if let tab = activeTab {
                    let md = "[\(tab.displayTitle)](\(tab.urlString))"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                    browserState.isSiteControlCenterPresented = false
                    browserState.showToast("Copied Markdown link")
                }
            } label: {
                Label("Copy Markdown Link", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                guard let host = activeTab?.simplifiedDomain else { return }
                let store = WKWebsiteDataStore.default()
                store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                    let matching = records.filter { $0.displayName.contains(host) }
                    store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matching) {
                        Task { @MainActor in
                            if let id = browserState.activeTabID {
                                WebViewPool.shared.reload(in: id)
                            }
                            browserState.isSiteControlCenterPresented = false
                            browserState.showToast("Cleared site data for \(host)")
                        }
                    }
                }
            } label: {
                Label("Clear Cookies & Cache for Site", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, y: 8)
    }
}

// MARK: - Arc Space Background (Vibrancy + Multi-Stop Gradient + Analog Grain)

struct ArcSpaceBackgroundView: View {
    let theme: SpaceTheme

    var body: some View {
        let colors = theme.renderedGradientColors
        ZStack {
            if theme.isVibrant {
                VisualEffectBlurView(
                    material: theme.prefersLightForeground ? .sidebar : .headerView,
                    blendingMode: .behindWindow
                )
            }

            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(theme.isVibrant ? 0.91 : 1.0)

            if colors.count >= 2 {
                RadialGradient(
                    colors: [
                        colors.last!.opacity(0.45 * theme.intensityFactor),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 15,
                    endRadius: 560
                )
            }

            if theme.grainIntensity > 0.02 {
                ArcGrainTextureOverlay(
                    intensity: theme.grainIntensity,
                    isDarkTheme: theme.prefersLightForeground
                )
                .blendMode(.overlay)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: theme)
    }
}

struct ArcGrainTextureOverlay: View {
    let intensity: Double
    let isDarkTheme: Bool

    private static let cachedNoiseImage: NSImage = {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(size * size) {
            rng ^= rng >> 12
            rng ^= rng << 25
            rng ^= rng >> 27
            let val = UInt8((rng &* 0x2545F4914F6CDD1D >> 56) & 0xFF)
            let idx = i * 4
            pixels[idx] = val
            pixels[idx + 1] = val
            pixels[idx + 2] = val
            pixels[idx + 3] = 28
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let cgImage = CGImage(
               width: size,
               height: size,
               bitsPerComponent: 8,
               bitsPerPixel: 32,
               bytesPerRow: size * 4,
               space: colorSpace,
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
               provider: provider,
               decode: nil,
               shouldInterpolate: false,
               intent: .defaultIntent
           ) {
            return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        }
        return NSImage()
    }()

    var body: some View {
        let grainImg = ArcAssetLoader.shared.textureImage(named: "grain") ?? Self.cachedNoiseImage
        Image(nsImage: grainImg)
            .resizable(resizingMode: .tile)
            .opacity(min(max(intensity * 0.55, 0), 0.75))
    }
}

struct VisualEffectBlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct SidebarResizeHandle: View {
    @Binding var sidebarWidth: CGFloat
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.white.opacity(0.28) : Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let proposed = sidebarWidth + value.translation.width
                        sidebarWidth = min(max(proposed, 200), 420)
                    }
            )
    }
}
