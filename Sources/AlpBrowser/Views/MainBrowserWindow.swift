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
                        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: browserState.isLibrarySheetPresented)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    SidebarResizeHandle(sidebarWidth: $browserState.sidebarWidth)
                }

                // Inset Web Viewport (Remains stationary; only the sidebar space slides)
                viewportArea
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                    .padding(.leading, browserState.isSidebarCollapsed ? 8 : 2)
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
            }
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

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newWidth = min(max(sidebarWidth + value.translation.width, 180), 380)
                        sidebarWidth = newWidth
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
