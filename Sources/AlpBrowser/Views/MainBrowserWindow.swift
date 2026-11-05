//
//  MainBrowserWindow.swift
//  Alp Browser
//
//  Main application window with frosted space backdrop, split view, and overlays.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import WebKit
import AppKit

public struct MainBrowserWindow: View {
    @EnvironmentObject var browserState: BrowserState

    public init() {}

    public var body: some View {
        ZStack {
            // 1. Frosted Space Background with procedural grain
            AlpSpaceBackgroundView(theme: browserState.activeTheme)
                .ignoresSafeArea()

            // 2. Main Content Split Layout
            HStack(spacing: 0) {
                if !browserState.isSidebarCollapsed {
                    let currentWidth = browserState.isLibrarySheetPresented ? max(browserState.sidebarWidth, 330) : browserState.sidebarWidth
                    SidebarView()
                        .frame(width: currentWidth)
                        .clipped()
                        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: browserState.isLibrarySheetPresented)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    SidebarResizeHandle(sidebarWidth: $browserState.sidebarWidth)
                }

                // Inset Web Viewport (Remains stationary; only the sidebar space slides)
                viewportArea
                    // With the sidebar hidden the page starts below the navigation strip, never under the traffic lights.
                    .padding(.top, browserState.isSidebarCollapsed ? CollapsedNavStripMetrics.contentTopInset : 8)
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                    .padding(.leading, browserState.isSidebarCollapsed ? 8 : 2)
            }
            .ignoresSafeArea(.all, edges: .top)

            // 2b. Collapsed-sidebar navigation strip (URL pill beside the traffic lights)
            if browserState.isSidebarCollapsed {
                CollapsedNavStripView()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            // 3. Collapsed Sidebar Edge Hover Trigger
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
                                AlpSpaceBackgroundView(theme: browserState.activeTheme)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.45), radius: 26, x: 8, y: 8)
                            .padding(.leading, 8)
                            // Flush with the top so the nav row sits on the traffic-light centre line.
                            .padding(.top, 0)
                            .padding(.bottom, 8)
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

            // 4. Overlays (Site Control, Theme Picker, Find Bar, Style Studio)
            if browserState.isSiteControlCenterPresented {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            browserState.isSiteControlCenterPresented = false
                        }
                    }
            }

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        if browserState.isSiteControlCenterPresented {
                            SiteControlCenterPopoverView()
                                .padding(.leading, max(14, browserState.sidebarWidth - 180))
                                .padding(.top, 76)
                                .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
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
                        if browserState.isFindBarPresented {
                            FindBarView()
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if browserState.isStyleStudioPresented {
                            StyleStudioView()
                                .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 20)
                }
                Spacer()
            }

            // 5. Quick Peek Modal
            if let peek = browserState.peekSession {
                PeekOverlayView(session: peek)
                    .id(peek.id)   // a new peek must rebuild the overlay, not reuse the old page's state
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // 6. Visual Tab Switcher (Control + Tab)
            if browserState.isTabSwitcherPresented {
                VisualTabSwitcherOverlayView()
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // 7. Command Bar (⌘T / ⌘L)
            if browserState.isCommandBarPresented {
                CommandBarView()
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            // 8. Toast Notification Pill
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
        .ignoresSafeArea(.all)
        .onExitCommand {
            if browserState.isCommandBarPresented {
                browserState.isCommandBarPresented = false
            } else if browserState.isLibrarySheetPresented {
                browserState.isLibrarySheetPresented = false
            } else if browserState.isSiteControlCenterPresented {
                browserState.isSiteControlCenterPresented = false
            } else if browserState.peekSession != nil {
                browserState.peekSession = nil
            }
        }
        .sheet(isPresented: $browserState.isSettingsPresented) {
            SettingsView()
                .environmentObject(browserState)
        }
    }

    // MARK: - Viewport Area (Single Tab or Split Panes)

    @ViewBuilder
    private var viewportArea: some View {
        let visibleIDs = browserState.visibleViewportTabIDs
        let tabs = visibleIDs.compactMap { browserState.findTab(id: $0) }

        if tabs.count == 2 {
            GeometryReader { geo in
                if browserState.activeSpace.splitOrientation == .horizontal {
                    let dividerWidth: CGFloat = 8
                    let availableWidth = max(200, geo.size.width - dividerWidth)
                    let leftWidth = max(180, min(availableWidth - 180, availableWidth * browserState.splitRatio))
                    let rightWidth = availableWidth - leftWidth

                    HStack(spacing: 0) {
                        ViewportPaneView(
                            tab: tabs[0],
                            isSplitMode: true,
                            isFocusedPane: browserState.activeTabID == tabs[0].id
                        )
                        .frame(width: leftWidth)

                        SplitDividerView(isHorizontal: true, ratio: $browserState.splitRatio, extent: availableWidth)

                        ViewportPaneView(
                            tab: tabs[1],
                            isSplitMode: true,
                            isFocusedPane: browserState.activeTabID == tabs[1].id
                        )
                        .frame(width: rightWidth)
                    }
                } else {
                    let dividerHeight: CGFloat = 8
                    let availableHeight = max(200, geo.size.height - dividerHeight)
                    let topHeight = max(140, min(availableHeight - 140, availableHeight * browserState.splitRatio))
                    let bottomHeight = availableHeight - topHeight

                    VStack(spacing: 0) {
                        ViewportPaneView(
                            tab: tabs[0],
                            isSplitMode: true,
                            isFocusedPane: browserState.activeTabID == tabs[0].id
                        )
                        .frame(height: topHeight)

                        SplitDividerView(isHorizontal: false, ratio: $browserState.splitRatio, extent: availableHeight)

                        ViewportPaneView(
                            tab: tabs[1],
                            isSplitMode: true,
                            isFocusedPane: browserState.activeTabID == tabs[1].id
                        )
                        .frame(height: bottomHeight)
                    }
                }
            }
        } else if tabs.count > 2 {
            MultiPaneSplitView(
                tabs: tabs,
                isHorizontal: browserState.activeSpace.splitOrientation == .horizontal
            )
        } else if let singleTab = tabs.first ?? browserState.activeTab {
            ViewportPaneView(
                tab: singleTab,
                isSplitMode: false,
                isFocusedPane: true
            )
        } else {
            Color.clear
        }
    }
}

// MARK: - Collapsed Sidebar Navigation Strip

/// One shared vertical centre for everything in the top band: the system traffic lights
/// (repositioned by `AlpWindowChrome`), the toggle/back/forward/reload icons and the URL pill.
enum AlpTopBarMetrics {
    /// Height of the slim titlebar band.
    static let bandHeight: CGFloat = 28
    /// Distance from the window's top edge to the shared centre line.
    static let centerY: CGFloat = bandHeight / 2
    static let iconSize: CGFloat = 24
    static let iconGlyphSize: CGFloat = 12
    static let iconSpacing: CGFloat = 2
    /// Horizontal space reserved for the traffic lights.
    static let trafficLightInset: CGFloat = 72
}

/// A toolbar icon button on the shared top-bar geometry (same frame and glyph size everywhere).
struct AlpTopBarIconButton: View {
    let symbol: String
    let help: String
    let theme: SpaceTheme
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: AlpTopBarMetrics.iconGlyphSize, weight: .medium))
                .frame(width: AlpTopBarMetrics.iconSize, height: AlpTopBarMetrics.iconSize)
                .opacity(isEnabled ? 1.0 : 0.35)
        }
        .buttonStyle(AlpIconButtonStyle(theme: theme))
        .disabled(!isEnabled)
        .help(help)
    }
}

enum CollapsedNavStripMetrics {
    /// Height of the titlebar band (shared with the sidebar's nav row).
    static let bandHeight: CGFloat = AlpTopBarMetrics.bandHeight
    /// Where the page starts: the band plus a small gap so the pill never touches the page.
    static let contentTopInset: CGFloat = bandHeight + 4
    static let pillHeight: CGFloat = 24
    static let pillMaxWidth: CGFloat = 520
    /// Space reserved at each side: traffic lights + toggle/back/forward on the left, mirrored on the right
    /// so the pill stays centred on the window.
    static let sideInset: CGFloat = AlpTopBarMetrics.trafficLightInset
        + 3 * AlpTopBarMetrics.iconSize + 2 * AlpTopBarMetrics.iconSpacing + 16
}

/// Titlebar band shown while the sidebar is hidden: toggle / back / forward beside the traffic lights and a
/// centered, frosted URL pill for the active tab. Clicking the pill opens the command bar (⌘L does the same).
struct CollapsedNavStripView: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        GeometryReader { geo in
            let inset = CollapsedNavStripMetrics.sideInset
            // Centered on the window, but never wide enough to reach the icons or the right edge.
            let width = max(160, min(CollapsedNavStripMetrics.pillMaxWidth, geo.size.width - inset * 2))
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Spacer(minLength: inset)
                    NavPill(tab: browserState.activeTab, theme: browserState.activeTheme)
                        .frame(width: width, height: CollapsedNavStripMetrics.pillHeight)
                    Spacer(minLength: inset)
                }

                HStack(spacing: AlpTopBarMetrics.iconSpacing) {
                    let theme = browserState.activeTheme
                    AlpTopBarIconButton(symbol: "sidebar.left", help: "Toggle Sidebar (⌘S)", theme: theme) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            browserState.isSidebarCollapsed.toggle()
                            browserState.isSidebarHoverPeeking = false
                        }
                    }
                    AlpTopBarIconButton(
                        symbol: "chevron.left", help: "Back (⌘[)", theme: theme,
                        isEnabled: browserState.canGoBackInActiveTab
                    ) { browserState.goBackInActiveTab() }
                    AlpTopBarIconButton(
                        symbol: "chevron.right", help: "Forward (⌘])", theme: theme,
                        isEnabled: browserState.canGoForwardInActiveTab
                    ) { browserState.goForwardInActiveTab() }
                }
                .padding(.leading, AlpTopBarMetrics.trafficLightInset)
            }
            .frame(width: geo.size.width, height: CollapsedNavStripMetrics.bandHeight)
        }
        .frame(height: CollapsedNavStripMetrics.bandHeight)
    }

    private struct NavPill: View {
        @EnvironmentObject var browserState: BrowserState
        let tab: TabItem?
        let theme: SpaceTheme

        private var isWeb: Bool { tab.map { $0.kind == .web && !$0.isBlank } ?? false }

        var body: some View {
            HStack(spacing: 8) {
                Button {
                    browserState.openCommandBar(prefilledWithCurrentURL: true)
                } label: {
                    HStack(spacing: 7) {
                        leadingGlyph
                        label
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Search or enter a URL (⌘L)")

                if isWeb {
                    Button {
                        browserState.reloadActiveTab()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.secondaryForegroundColor)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reload Page (⌘R)")
                }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(
                ZStack {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                    Capsule(style: .continuous).fill(theme.primaryColor.swiftUIColor.opacity(0.14))
                }
            )
            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        }

        @ViewBuilder
        private var leadingGlyph: some View {
            if tab?.isLoading == true {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if let tab, isWeb {
                Image(systemName: tab.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 12, height: 12)
            }
        }

        @ViewBuilder
        private var label: some View {
            if let tab, isWeb {
                let domain = tab.simplifiedDomain
                let title = tab.displayTitle
                HStack(spacing: 6) {
                    Text(domain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.foregroundColor.opacity(0.95))
                        .lineLimit(1)
                    if title != domain {
                        Text(title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(theme.secondaryForegroundColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            } else if let tab, !tab.isBlank {
                Text(tab.displayTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.foregroundColor.opacity(0.95))
                    .lineLimit(1)
            } else {
                Text("Search or Enter URL…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Split View Drag Divider

struct SplitDividerView: View {
    let isHorizontal: Bool
    /// Share of `extent` given to the first pane, kept within `range`.
    @Binding var ratio: CGFloat
    /// Length along the drag axis that the ratio is measured against (the space the two panes share).
    let extent: CGFloat
    var range: ClosedRange<CGFloat> = 0.2...0.8
    /// Called when a drag ends or the divider is reset (the 2-pane default persists `splitRatio`).
    var onCommit: () -> Void = { BrowserState.shared.scheduleSave() }

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var cursorPushed = false
    /// Ratio when the current drag began; the drag is applied to this, not accumulated per event,
    /// so a skipped or coalesced event can never lose movement.
    @State private var startRatio: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: isHorizontal ? 8 : nil, height: isHorizontal ? nil : 8)
                .contentShape(Rectangle())

            if isHovered || isDragging {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.40))
                    .frame(width: isHorizontal ? 2 : 36, height: isHorizontal ? 36 : 2)
            }
        }
        .frame(width: isHorizontal ? 8 : nil, height: isHorizontal ? nil : 8)
        .onHover { hovering in
            isHovered = hovering
            if hovering { pushCursor() } else if !isDragging { popCursor() }
        }
        .onDisappear { popCursor() }
        .onTapGesture(count: 2) {
            // Double-click resets to an even split.
            ratio = min(range.upperBound, max(range.lowerBound, 0.5))
            onCommit()
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    guard extent > 0 else { return }
                    if startRatio == nil {
                        startRatio = ratio
                        isDragging = true
                    }
                    let travelled = isHorizontal ? value.translation.width : value.translation.height
                    ratio = max(range.lowerBound, min(range.upperBound, (startRatio ?? ratio) + travelled / extent))
                }
                .onEnded { _ in
                    startRatio = nil
                    isDragging = false
                    if !isHovered { popCursor() }
                    onCommit()
                }
        )
        .help("Drag to resize, double-click to reset")
    }

    private func pushCursor() {
        guard !cursorPushed else { return }
        cursorPushed = true
        (isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
    }

    private func popCursor() {
        guard cursorPushed else { return }
        cursorPushed = false
        NSCursor.pop()
    }
}

// MARK: - Split View with 3 or 4 Panes

/// Lays out three or four panes with a draggable divider between every adjacent pair. Dragging a divider
/// moves space between its two neighbours only. Sizes live in `@State` while dragging (so the whole app
/// is not re-rendered per mouse event) and are written to the space when the drag ends.
struct MultiPaneSplitView: View {
    @EnvironmentObject var browserState: BrowserState
    let tabs: [TabItem]
    let isHorizontal: Bool

    @State private var liveFractions: [Double]?

    private let dividerThickness: CGFloat = 8

    private var fractions: [Double] {
        SplitPaneLayout.normalized(liveFractions ?? browserState.activeSpace.splitFractions, count: tabs.count)
    }

    var body: some View {
        GeometryReader { geo in
            let total = isHorizontal ? geo.size.width : geo.size.height
            let extent = max(1, total - dividerThickness * CGFloat(tabs.count - 1))
            let sizes = fractions
            if isHorizontal {
                HStack(spacing: 0) { paneRow(sizes: sizes, extent: extent) }
            } else {
                VStack(spacing: 0) { paneRow(sizes: sizes, extent: extent) }
            }
        }
    }

    @ViewBuilder
    private func paneRow(sizes: [Double], extent: CGFloat) -> some View {
        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
            ViewportPaneView(
                tab: tab,
                isSplitMode: true,
                isFocusedPane: browserState.activeTabID == tab.id
            )
            .frame(
                width: isHorizontal ? extent * CGFloat(sizes[index]) : nil,
                height: isHorizontal ? nil : extent * CGFloat(sizes[index])
            )

            if index < tabs.count - 1 {
                divider(after: index, sizes: sizes, extent: extent)
            }
        }
    }

    private func divider(after index: Int, sizes: [Double], extent: CGFloat) -> some View {
        let pairShare = SplitPaneLayout.pairShare(sizes, boundary: index)
        let pairExtent = extent * CGFloat(sizes[index] + sizes[index + 1])
        let allowed = SplitPaneLayout.pairShareRange(sizes, boundary: index)
        return SplitDividerView(
            isHorizontal: isHorizontal,
            ratio: Binding(
                get: { CGFloat(pairShare) },
                set: { newShare in
                    // Always resize from the sizes at the start of this render, so a drag never compounds.
                    liveFractions = SplitPaneLayout.settingPairShare(sizes, boundary: index, share: Double(newShare))
                }
            ),
            extent: pairExtent,
            range: CGFloat(allowed.lowerBound)...CGFloat(allowed.upperBound),
            onCommit: {
                if let live = liveFractions { browserState.setSplitFractions(live) }
                liveFractions = nil
            }
        )
    }
}

// MARK: - Procedural Space Background View

public struct AlpSpaceBackgroundView: View {
    public let theme: SpaceTheme

    public init(theme: SpaceTheme) {
        self.theme = theme
    }

    public var body: some View {
        LinearGradient(
            colors: theme.renderedGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Sidebar Resize Handle

struct SidebarResizeHandle: View {
    @Binding var sidebarWidth: CGFloat
    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat = 256

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 14)
                .contentShape(Rectangle())

            if isDragging {
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1.5)
            }
        }
        .frame(width: 14)
        .padding(.horizontal, -6)
        .zIndex(100)
        .onHover { inside in
            if inside || isDragging {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartWidth = sidebarWidth
                    }
                    let proposed = dragStartWidth + value.translation.width
                    let clamped = min(max(proposed, 200), 460)
                    sidebarWidth = clamped
                }
                .onEnded { _ in
                    isDragging = false
                    BrowserState.shared.scheduleSave()
                }
        )
    }
}
