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

    @State private var copiedURLFeedback = false
    @State private var renamingTabID: UUID?
    @State private var renameDraft: String = ""

    private var theme: SpaceTheme {
        browserState.activeTheme
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            // 1. Top Navigation Row (Clearance for macOS traffic lights)
            topNavigationRow
                .padding(.top, 8)
                .padding(.horizontal, 12)

            // 2. Command / URL Bar Pill
            urlCommandPill
                .padding(.horizontal, 10)

            // 3. Favorites Grid (Top pinned apps)
            if !browserState.favorites.isEmpty {
                favoritesGrid
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }

            // 4. Interactive Horizontal Space Pager
            SidebarSpaceContentView(
                renamingTabID: $renamingTabID,
                renameDraft: $renameDraft
            )

            // 5. Media Mini-Player Card (when background tab is playing audio)
            if let audioTab = browserState.backgroundAudioPlayingTab {
                sidebarMediaMiniPlayer(for: audioTab)
                    .padding(.horizontal, 10)
            }

            // 6. Memory Monitor Pill
            memoryFooter
                .padding(.horizontal, 10)

            // 7. Bottom Space Switcher & Library Bar
            bottomSpaceSwitcherBar
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .foregroundStyle(theme.foregroundColor)
    }

    // MARK: - 1. Top Navigation Row

    private var topNavigationRow: some View {
        HStack(spacing: 8) {
            if !browserState.isSidebarCollapsed {
                Spacer().frame(width: 64)
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    browserState.isSidebarCollapsed.toggle()
                    browserState.isSidebarHoverPeeking = false
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .help("Toggle Sidebar (⌘S)")

            Spacer()

            Button {
                browserState.goBackInActiveTab()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .opacity(browserState.canGoForwardInActiveTab ? 1.0 : 0.35)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .disabled(!browserState.canGoForwardInActiveTab)
            .help("Forward (⌘])")

            Button {
                if let id = browserState.activeTabID {
                    WebViewPool.shared.reload(in: id)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .help("Reload (⌘R)")
        }
    }

    // MARK: - 2. URL Command Pill

    private var urlCommandPill: some View {
        HStack(spacing: 7) {
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                    browserState.isSiteControlCenterPresented.toggle()
                }
            } label: {
                Image(systemName: browserState.activeTab?.urlString.hasPrefix("https") == true ? "lock.fill" : "slider.horizontal.3")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Site Security & Privacy Controls")

            Button {
                browserState.openCommandBar(prefilledWithCurrentURL: true)
            } label: {
                HStack {
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

            Button {
                if let url = browserState.activeTab?.urlString {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    copiedURLFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedURLFeedback = false
                    }
                }
            } label: {
                Image(systemName: copiedURLFeedback ? "checkmark" : "link")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
            }
            .buttonStyle(.plain)
            .help("Copy Current URL (⌘⇧C)")

            Button {
                browserState.addSplitPane()
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
            }
            .buttonStyle(.plain)
            .help("Add Split View (⌃⇧=)")

            Button {
                browserState.isStyleStudioPresented.toggle()
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.effectiveAccentColor)
            }
            .buttonStyle(.plain)
            .help("Customize Page Style")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.pillBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.pillBorderColor, lineWidth: 0.8)
                )
        )
    }

    // MARK: - 3. Favorites Grid

    private var favoritesGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.pillBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.pillBorderColor, lineWidth: 0.6))
        )
    }

    // MARK: - 6. Memory Footer

    private var memoryFooter: some View {
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5.5, height: 5.5)
                Text(String(format: "%.0f MB RAM", browserState.currentProcessMemoryMB))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryForegroundColor)
            }

            Spacer()

            Button {
                Task {
                    await browserState.hibernateAllBackgroundTabsNow()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 9.5))
                    Text("Hibernate")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(theme.secondaryForegroundColor)
            }
            .buttonStyle(.plain)
            .help("Unload Background Tabs (0 MB RAM)")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 7. Bottom Space Switcher & Library Bar

    private var bottomSpaceSwitcherBar: some View {
        HStack(spacing: 8) {
            Button {
                browserState.isLibrarySheetPresented = true
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .help("Library (Archive, Canvas, Notes, Styles)")

            Button {
                browserState.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AlpIconButtonStyle(theme: theme))
            .help("Settings & App Icons")

            Spacer()

            // Space Indicator Pills
            HStack(spacing: 6) {
                ForEach(Array(browserState.spaces.enumerated()), id: \.element.id) { index, space in
                    let isSelected = (browserState.activeSpaceID == space.id)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
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

            Spacer()

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
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add Space or Note")
        }
    }
}

// MARK: - Space Content ScrollView (Pinned + Active/Today Tabs)

struct SidebarSpaceContentView: View {
    @EnvironmentObject var browserState: BrowserState
    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String

    private var theme: SpaceTheme {
        browserState.activeTheme
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                // Pinned Items Section
                if !browserState.activeSpace.pinnedNodes.isEmpty {
                    ForEach(browserState.activeSpace.pinnedNodes) { node in
                        SidebarNodeRowView(
                            node: node,
                            renamingTabID: $renamingTabID,
                            renameDraft: $renameDraft,
                            theme: theme
                        )
                    }
                }

                // Section Divider
                HStack {
                    Text("ACTIVE TABS")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .tracking(0.6)
                    Spacer()
                    Button {
                        browserState.openNewTab(urlString: "https://www.google.com")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(theme.secondaryForegroundColor)
                    }
                    .buttonStyle(.plain)
                    .help("New Tab (⌘T)")
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 2)

                // Today Tabs
                ForEach(browserState.activeSpace.todayTabs) { tab in
                    TabRowItemView(
                        tab: tab,
                        isPinned: false,
                        isSelected: browserState.activeTabID == tab.id,
                        renamingTabID: $renamingTabID,
                        renameDraft: $renameDraft,
                        theme: theme
                    )
                }

                if browserState.activeSpace.todayTabs.isEmpty && browserState.activeSpace.pinnedNodes.isEmpty {
                    VStack(spacing: 8) {
                        Text("No open tabs")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.secondaryForegroundColor)
                        Button("Open Tab") {
                            browserState.openNewTab(urlString: "https://www.google.com")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
            .padding(.horizontal, 8)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
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
                        .padding(.leading, 14)
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
        HStack(spacing: 8) {
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

            // Audio Indicator
            if tab.isPlayingAudio {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.effectiveAccentColor)
            }

            // Close Button (Fixed: always "xmark", never minus!)
            if isHovered || isSelected {
                Button {
                    browserState.handleTabTrailingButtonAction(for: tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.foregroundColor)
                }
            }
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tab.displayTitle)
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
