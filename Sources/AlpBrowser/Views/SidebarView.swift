//
//  SidebarView.swift
//  Alp Browser
//
//  3-tier frosted glass sidebar with spaces, pinned tabs, and favorites.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit

public struct SidebarView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var renamingTabID: UUID?
    @State private var renameDraft: String = ""
    @State private var isHoveringUrlPill = false

    private var theme: SpaceTheme {
        browserState.activeTheme
    }

    public init() {}

    public var body: some View {
        Group {
            if browserState.isLibrarySheetPresented {
                SidebarLibraryView()
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
            } else {
                VStack(spacing: 8) {
                    // 1. Top Navigation Row (Seamless with macOS traffic lights)
                    topNavigationRow
                        .padding(.top, 12)
                        .padding(.horizontal, 6)

                    // 2. Command / URL Bar Pill with hover "..." menu
                    urlCommandPill
                        .padding(.horizontal, 6)

                    // 3. Favorites Grid (2x2 layout for 4 bookmarks)
                    if !browserState.favorites.isEmpty {
                        favoritesGrid
                            .padding(.horizontal, 6)
                            .padding(.top, 2)
                    }

                    // 4. Interactive Horizontal Space Pager with smooth slide transition
                    SidebarSpaceContentView(
                        renamingTabID: $renamingTabID,
                        renameDraft: $renameDraft
                    )

                    // 5. Media Mini-Player Card (when background tab is playing audio)
                    if let audioTab = browserState.backgroundAudioPlayingTab {
                        sidebarMediaMiniPlayer(for: audioTab)
                            .padding(.horizontal, 6)
                    }

                    // 6. Bottom Space Switcher & Library Bar (Stable during sidebar resizing)
                    bottomSpaceSwitcherBar
                        .padding(.horizontal, 6)
                        .padding(.bottom, 10)
                }
                .foregroundStyle(theme.foregroundColor)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: browserState.isLibrarySheetPresented)
    }

    // MARK: - 1. Top Navigation Row

    private var topNavigationRow: some View {
        HStack(spacing: 6) {
            if !browserState.isSidebarCollapsed {
                // Exact width clearance for macOS window traffic lights (dots)
                Spacer()
                    .frame(width: 68)
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    browserState.isSidebarCollapsed.toggle()
                    browserState.isSidebarHoverPeeking = false
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .help("Toggle Sidebar (⌘S)")

            Spacer()

            Button {
                browserState.goBackInActiveTab()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .opacity(browserState.canGoBackInActiveTab ? 1.0 : 0.35)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .disabled(!browserState.canGoBackInActiveTab)
            .help("Back (⌘[)")

            Button {
                browserState.goForwardInActiveTab()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .opacity(browserState.canGoForwardInActiveTab ? 1.0 : 0.35)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .disabled(!browserState.canGoForwardInActiveTab)
            .help("Forward (⌘])")

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                    browserState.isSiteControlCenterPresented.toggle()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .help("Site Options & Controls")
        }
        .frame(height: 26)
    }

    // MARK: - 2. Clean URL Command Pill with Site Controls & Extensions

    private var urlCommandPill: some View {
        HStack(spacing: 6) {
            // Domain / URL Title Area (Click opens Command Bar ⌘T / ⌘L)
            Button {
                browserState.openCommandBar(prefilledWithCurrentURL: true)
            } label: {
                HStack(spacing: 5) {
                    Text(browserState.activeTab?.simplifiedDomain ?? "Search or Enter URL...")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(theme.foregroundColor.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Right side of URL bubble (Exact Arc layout from user screenshot):
            // 1. Pink Adblock / Privacy Shield
            Image(systemName: "shield.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.55))

            // 2. Copy Link Button
            Button {
                if let url = browserState.activeTab?.urlString {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    browserState.showToast("Copied link to clipboard")
                }
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Copy URL")

            // 3. Site Controls / Tune Button (Opens Arc Site Control Center)
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                    browserState.isSiteControlCenterPresented.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Site Controls & Extensions")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.pillBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(theme.pillBorderColor, lineWidth: 0.8)
                )
        )
    }

    // MARK: - 3. Favorites Grid (2 Columns -> 2x2 for 4 Bookmarks)

    private var favoritesGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(browserState.favorites) { tab in
                FavoriteTileView(
                    tab: tab,
                    isSelected: browserState.activeTabID == tab.id,
                    theme: theme
                ) {
                    browserState.selectTab(tab.id)
                }
            }
        }
    }

    // MARK: - 5. Media Mini-Player

    private func sidebarMediaMiniPlayer(for tab: TabItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.effectiveAccentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(tab.simplifiedDomain)
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.secondaryForegroundColor)
            }

            Spacer()

            Button {
                WebViewPool.shared.toggleMediaPlayback(in: tab.id)
            } label: {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)

            Button {
                browserState.selectTab(tab.id)
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.pillBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.pillBorderColor, lineWidth: 0.6))
        )
    }

    // MARK: - 6. Bottom Space Switcher & Library Bar (Stable during sidebar resizing)

    private var bottomSpaceSwitcherBar: some View {
        HStack(spacing: 4) {
            // Left: Library and Settings
            HStack(spacing: 2) {
                Button {
                    browserState.isLibrarySheetPresented = true
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(AlpIconButtonStyle(theme: theme))
                .help("Library (Archive, Canvas, Notes, Styles)")

                Button {
                    browserState.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(AlpIconButtonStyle(theme: theme))
                .help("Settings & App Icons (⌘,)")
            }
            .fixedSize()

            Spacer(minLength: 4)

            // Center: Space Indicator Pills
            HStack(spacing: 4) {
                ForEach(Array(browserState.spaces.enumerated()), id: \.element.id) { index, space in
                    let isSelected = (browserState.activeSpaceID == space.id)
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            browserState.switchToSpace(at: index)
                        }
                    } label: {
                        Text(space.iconEmoji)
                            .font(.system(size: 13))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? theme.selectionBackground : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isSelected ? theme.effectiveAccentColor.opacity(0.8) : Color.clear, lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("\(space.title) Space")
                }
            }
            .fixedSize()

            Spacer(minLength: 4)

            // Right: New Space / Canvas / Note Menu
            Menu {
                Button("New Space") {
                    let newSpace = AlpSpace(
                        title: "Space \(browserState.spaces.count + 1)",
                        iconEmoji: "🪐",
                        theme: .auroraMesh
                    )
                    browserState.spaces.append(newSpace)
                    browserState.activeSpaceID = newSpace.id
                    browserState.scheduleSave()
                }
                Button("New Canvas") {
                    browserState.createNewCanvas()
                }
                Button("New Note") {
                    browserState.createNewNote()
                }
                Divider()
                Button("Theme Settings") {
                    browserState.isThemePickerPresented = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add Space or Note")
        }
    }
}

// MARK: - Space Content ScrollView with Smooth Horizontal Slide Pager Animation

struct SidebarSpaceContentView: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var gestures = TrackpadGestureManager.shared
    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String

    private var theme: SpaceTheme {
        browserState.activeTheme
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                let currentSpace = browserState.activeSpace

                VStack(alignment: .leading, spacing: 3) {
                    // Space Title Header matching Arc (e.g. "🧌 Personal")
                    HStack(spacing: 6) {
                        Text(currentSpace.iconEmoji)
                            .font(.system(size: 13))
                        Text(currentSpace.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.foregroundColor)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .padding(.bottom, 2)

                    // Pinned Items Section (Retained Members)
                    if !currentSpace.pinnedNodes.isEmpty {
                        ForEach(currentSpace.pinnedNodes) { node in
                            SidebarNodeRowView(
                                node: node,
                                renamingTabID: $renamingTabID,
                                renameDraft: $renameDraft,
                                theme: theme
                            )
                        }

                        // Subtle divider between retained items and temporary tabs
                        Rectangle()
                            .fill(theme.secondaryForegroundColor.opacity(0.18))
                            .frame(height: 1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }

                    // Temporary (Today) Tabs
                    ForEach(currentSpace.todayTabs) { tab in
                        TabRowItemView(
                            tab: tab,
                            isPinned: false,
                            isSelected: browserState.activeTabID == tab.id,
                            renamingTabID: $renamingTabID,
                            renameDraft: $renameDraft,
                            theme: theme
                        )
                    }

                    // "+ New Tab" row (opens Command Bar in center)
                    NewTabButtonRow(theme: theme)
                }
                .id(currentSpace.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: browserState.spaceTransitionDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: browserState.spaceTransitionDirection > 0 ? .leading : .trailing).combined(with: .opacity)
                    )
                )
            }
            .offset(x: gestures.sidebarSwipeOffset)
            .animation(.spring(response: 0.30, dampingFraction: 0.85), value: browserState.activeSpaceID)
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Row Views for Tabs and Nodes

struct SidebarNodeRowView: View {
    let node: SidebarNode
    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String
    let theme: SpaceTheme

    var body: some View {
        switch node {
        case .tab(let tab):
            TabRowItemView(
                tab: tab,
                isPinned: true,
                isSelected: BrowserState.shared.activeTabID == tab.id,
                renamingTabID: $renamingTabID,
                renameDraft: $renameDraft,
                theme: theme
            )
        case .folder(let folder):
            FolderRowItemView(
                folder: folder,
                renamingTabID: $renamingTabID,
                renameDraft: $renameDraft,
                theme: theme
            )
        }
    }
}

struct FolderRowItemView: View {
    @EnvironmentObject var browserState: BrowserState
    let folder: FolderItem
    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String
    let theme: SpaceTheme

    @State private var isExpanded: Bool

    init(folder: FolderItem, renamingTabID: Binding<UUID?>, renameDraft: Binding<String>, theme: SpaceTheme) {
        self.folder = folder
        self._renamingTabID = renamingTabID
        self._renameDraft = renameDraft
        self.theme = theme
        self._isExpanded = State(initialValue: folder.isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                    browserState.toggleFolderExpanded(folderID: folder.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: 12)

                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.effectiveAccentColor)

                    Text(folder.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.foregroundColor)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(folder.children) { child in
                        SidebarNodeRowView(
                            node: child,
                            renamingTabID: $renamingTabID,
                            renameDraft: $renameDraft,
                            theme: theme
                        )
                        .padding(.leading, 12)
                    }
                }
            }
        }
    }
}

struct TabRowItemView: View {
    @EnvironmentObject var browserState: BrowserState
    let tab: TabItem
    let isPinned: Bool
    let isSelected: Bool
    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String
    let theme: SpaceTheme

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            // Favicon or Kind Icon
            Group {
                if let fav = FaviconCache.shared.favicon(for: tab.urlString) {
                    Image(nsImage: fav)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                } else {
                    switch tab.kind {
                    case .web:
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryForegroundColor)
                    case .canvas:
                        Image(systemName: "scribble")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.effectiveAccentColor)
                    case .note:
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.effectiveAccentColor)
                    }
                }
            }
            .frame(width: 16, height: 16)

            // Title or Renaming TextField
            if renamingTabID == tab.id {
                TextField("Tab Title", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .onSubmit {
                        browserState.mutateTab(id: tab.id) { $0.customTitle = renameDraft }
                        renamingTabID = nil
                    }
            } else {
                Text(tab.displayTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.foregroundColor : theme.foregroundColor.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Audio Playing Indicator
            if tab.isPlayingAudio {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.effectiveAccentColor)
            }

            // Close / Unload Button:
            // - Active retained tab (isSelected && isPinned): shows minus sign ("minus") to unload.
            // - Temporary tab (!isPinned): shows close X ("xmark") only when hovered.
            // - Inactive tab (isHovered): shows close X ("xmark").
            let showMinus = isSelected && isPinned
            let showTrailingButton = (isSelected && isPinned) || isHovered
            if showTrailingButton {
                Button {
                    browserState.handleTabTrailingButtonAction(for: tab)
                } label: {
                    Image(systemName: showMinus ? "minus" : "xmark")
                        .font(.system(size: showMinus ? 10.5 : 9.5, weight: .bold))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(showMinus ? "Unload Tab" : "Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? theme.selectionBackground : (isHovered ? theme.hoverBackground : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            browserState.selectTab(tab.id)
        }
        .contextMenu {
            Button(tab.isPinned ? "Move to Active Tabs" : "Pin Tab") {
                browserState.togglePinTab(id: tab.id)
            }
            Button("Rename Tab") {
                renameDraft = tab.displayTitle
                renamingTabID = tab.id
            }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.urlString, forType: .string)
            }
            Divider()
            Button("Close Tab") {
                browserState.closeTab(id: tab.id)
            }
        }
    }
}

struct FavoriteTileView: View {
    let tab: TabItem
    let isSelected: Bool
    let theme: SpaceTheme
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? theme.selectionBackground : (isHovered ? theme.hoverBackground : theme.pillBackground.opacity(0.6)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? theme.effectiveAccentColor.opacity(0.8) : theme.pillBorderColor, lineWidth: isSelected ? 1.2 : 0.6)
                    )

                if let fav = FaviconCache.shared.favicon(for: tab.urlString) {
                    Image(nsImage: fav)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.foregroundColor)
                }
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tab.displayTitle)
    }
}

struct NewTabButtonRow: View {
    @EnvironmentObject var browserState: BrowserState
    let theme: SpaceTheme
    @State private var isHovered = false

    var body: some View {
        Button {
            browserState.openCommandBar(prefilledWithCurrentURL: false)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? theme.foregroundColor : theme.secondaryForegroundColor)
                    .frame(width: 16, height: 16)

                Text("New Tab")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? theme.foregroundColor : theme.secondaryForegroundColor)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? theme.hoverBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("New Tab (⌘T)")
    }
}

struct AlpIconButtonStyle: ButtonStyle {
    let theme: SpaceTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.secondaryForegroundColor)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? theme.selectionBackground : Color.clear)
            )
    }
}
