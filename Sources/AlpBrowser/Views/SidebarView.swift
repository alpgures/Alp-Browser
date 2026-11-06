//
//  SidebarView.swift
//  Alp Browser
//
//  3-tier frosted glass sidebar with spaces, pinned tabs, and favorites.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SidebarView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var renamingTabID: UUID?
    @State private var renameDraft: String = ""
    @State private var isHoveringUrlPill = false
    @State private var renamingSpaceID: UUID?
    @State private var spaceNameDraft: String = ""
    @State private var spacePendingDeletion: AlpSpace?

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
                VStack(spacing: 10) {
                    // 1. Top Navigation Row (Seamless with macOS traffic lights)
                    // The row is exactly the band height, flush with the window top, so its centre
                    // is the traffic-light centre line.
                    topNavigationRow
                        .padding(.horizontal, 8)

                    // 2. Command / URL Bar Pill with hover "..." menu
                    urlCommandPill
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                    // 3. Favorites Grid (2x2 layout for 4 bookmarks)
                    if !browserState.favorites.isEmpty {
                        favoritesGrid
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                    }

                    // 4. Interactive Horizontal Space Pager with smooth slide transition
                    SidebarSpaceContentView(
                        renamingTabID: $renamingTabID,
                        renameDraft: $renameDraft
                    )
                    .padding(.horizontal, 8)

                    // 5. Media Mini-Player Card (when background tab is playing audio)
                    if let audioTab = browserState.backgroundAudioPlayingTab {
                        sidebarMediaMiniPlayer(for: audioTab)
                            .padding(.horizontal, 8)
                    }

                    // 6. Bottom Space Switcher & Library Bar (Stable during sidebar resizing)
                    bottomSpaceSwitcherBar
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .alert("Rename Space", isPresented: Binding(
            get: { renamingSpaceID != nil },
            set: { if !$0 { renamingSpaceID = nil } }
        )) {
            TextField("Space name", text: $spaceNameDraft)
            Button("Rename") {
                if let id = renamingSpaceID { browserState.renameSpace(id: id, to: spaceNameDraft) }
                renamingSpaceID = nil
            }
            Button("Cancel", role: .cancel) { renamingSpaceID = nil }
        }
        .confirmationDialog(
            "Delete “\(spacePendingDeletion?.title ?? "")”?",
            isPresented: Binding(
                get: { spacePendingDeletion != nil },
                set: { if !$0 { spacePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Space", role: .destructive) {
                if let space = spacePendingDeletion {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                        browserState.deleteSpace(id: space.id)
                    }
                }
                spacePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { spacePendingDeletion = nil }
        } message: {
            Text("Its open tabs are saved to the Archive. Its pinned tabs and folders are removed.")
        }
    }

    // MARK: - 1. Top Navigation Row

    private var topNavigationRow: some View {
        HStack(spacing: AlpTopBarMetrics.iconSpacing) {
            // Clearance for the macOS traffic lights, measured from the window edge: the row has 8pt
            // of horizontal padding, and the hover-peek panel (sidebar collapsed) is inset another 8pt.
            Spacer()
                .frame(width: AlpTopBarMetrics.trafficLightInset - (browserState.isSidebarCollapsed ? 16 : 8))

            AlpTopBarIconButton(symbol: "sidebar.left", help: "Toggle Sidebar (⌘S)", theme: theme) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    browserState.isSidebarCollapsed.toggle()
                    browserState.isSidebarHoverPeeking = false
                }
            }

            Spacer()

            if isNarrowSidebar {
                // Too narrow for three buttons beside the traffic lights: fold them into one menu.
                Menu {
                    Button("Back") { browserState.goBackInActiveTab() }
                        .disabled(!browserState.canGoBackInActiveTab)
                    Button("Forward") { browserState.goForwardInActiveTab() }
                        .disabled(!browserState.canGoForwardInActiveTab)
                    Button("Reload Page") { browserState.reloadActiveTab() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: AlpTopBarMetrics.iconGlyphSize, weight: .medium))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: AlpTopBarMetrics.iconSize, height: AlpTopBarMetrics.iconSize)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Back, Forward, Reload")
            } else {
                AlpTopBarIconButton(
                    symbol: "chevron.left", help: "Back (⌘[)", theme: theme,
                    isEnabled: browserState.canGoBackInActiveTab
                ) { browserState.goBackInActiveTab() }

                AlpTopBarIconButton(
                    symbol: "chevron.right", help: "Forward (⌘])", theme: theme,
                    isEnabled: browserState.canGoForwardInActiveTab
                ) { browserState.goForwardInActiveTab() }

                AlpTopBarIconButton(symbol: "arrow.clockwise", help: "Reload Page (⌘R)", theme: theme) {
                    browserState.reloadActiveTab()
                }
            }
        }
        .frame(height: AlpTopBarMetrics.bandHeight)
        .frame(maxWidth: .infinity)
        // The band is taller than the old 28 pt one so the controls sit lower; the pill below keeps its place.
        .padding(.bottom, -AlpTopBarMetrics.bandOverlapBelow)
    }

    /// True below Arc's narrow-sidebar width, where the top row and bottom bar use their compact forms.
    private var isNarrowSidebar: Bool {
        browserState.sidebarWidth < AlpSidebarMetrics.narrowWidth
    }

    // MARK: - 2. Clean URL Command Pill with Hover "..." Button

    private var urlCommandPill: some View {
        HStack(spacing: 6) {
            // Domain / URL Title Area (click opens the dropdown under the pill; a blank tab gets the centered bar)
            Button {
                browserState.openURLDropdown()
            } label: {
                HStack(spacing: 6) {
                    if browserState.activeTab?.isLoading == true {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 14, height: 14)
                    } else if let tab = browserState.activeTab, let fav = FaviconCache.shared.favicon(for: tab.urlString) {
                        Image(nsImage: fav)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                    }

                    Text(browserState.activeTab.flatMap { $0.isBlank ? nil : $0.simplifiedDomain } ?? "Search or Enter URL...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.foregroundColor.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // "..." button: always laid out (fixed 24x24 slot); hover only fades it in, so the pill never reflows.
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                    browserState.isSiteControlCenterPresented.toggle()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.hoverBackground)
                    )
            }
            .buttonStyle(.plain)
            .help("Site Controls & Options")
            .opacity(isHoveringUrlPill ? 1 : 0)
            .allowsHitTesting(isHoveringUrlPill)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 38)   // fixed: hover must never change the pill's size
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.pillBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.pillBorderColor, lineWidth: 0.8)
                )
        )
        .contentShape(Rectangle())
        .background(
            // Reports the pill's frame so the URL dropdown can anchor directly under it.
            GeometryReader { geo in
                Color.clear.preference(key: AlpURLPillFrameKey.self, value: geo.frame(in: .named(AlpURLPillFrameKey.space)))
            }
        )
        .onHover { isHoveringUrlPill = $0 }   // no animation: state only drives opacity
    }

    // MARK: - 3. Favorites Grid (2 Columns -> 2x2 for 4 Bookmarks)

    private var favoritesGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
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
        .frame(maxWidth: .infinity)
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
                    .lineLimit(1)
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

    /// Bottom bar: Library (folder) and Settings (gearshape) on the leading edge,
    /// the space switcher in the center (active space in pill frame, inactive spaces showing icon),
    /// and a "+ ⌵" on the trailing edge. Matches Arc screenshot ergonomics.
    private var bottomSpaceSwitcherBar: some View {
        ZStack {
            // Centre: space switcher
            spaceSwitcher
                // Clear of the side buttons: 44 pt covers the folder button or the "+" menu when narrow.
                .padding(.horizontal, isNarrowSidebar ? 44 : 76)

            HStack(spacing: 6) {
                // Leading: Library (folder)
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                        browserState.isLibrarySheetPresented = true
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AlpIconButtonStyle(theme: theme))
                .help("Library")

                // Leading: Settings (gearshape). Narrow sidebars move it into the "+" menu.
                if !isNarrowSidebar {
                    Button {
                        browserState.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(AlpIconButtonStyle(theme: theme))
                    .help("Settings (⌘,)")
                }

                Spacer(minLength: 0)

                // Trailing: "+ ⌵" (New Space / Folder / Easel / Note)
                Menu {
                    if isNarrowSidebar {
                        Button("Settings…") { browserState.isSettingsPresented = true }
                        Divider()
                    }
                    Button("New Space") {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            _ = browserState.createSpace()
                        }
                    }
                    Button("New Folder") {
                        browserState.createFolder()
                    }
                    Button("New Easel") {
                        browserState.createNewCanvas()
                    }
                    Button("New Note") {
                        browserState.createNewNote()
                    }
                    Divider()
                    Button("Edit Theme…") {
                        browserState.isThemePickerPresented = true
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(height: 32)
                    .padding(.horizontal, 5)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("New Space…")
            }
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
    }

    /// The space icons. Narrow sidebars centre them when they fit and scroll them sideways when they do not.
    @ViewBuilder
    private var spaceSwitcher: some View {
        if isNarrowSidebar {
            ViewThatFits(in: .horizontal) {
                spaceSwitcherIcons
                ScrollView(.horizontal, showsIndicators: false) { spaceSwitcherIcons }
            }
        } else {
            spaceSwitcherIcons
        }
    }

    private var spaceSwitcherIcons: some View {
        HStack(spacing: 8) {
            ForEach(Array(browserState.spaces.enumerated()), id: \.element.id) { index, space in
                SpaceSwitcherIcon(
                    space: space,
                    isActive: browserState.activeSpaceID == space.id,
                    theme: theme
                ) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                        browserState.switchToSpace(at: index)
                    }
                }
                .contextMenu {
                    Button("Rename Space…") {
                        spaceNameDraft = space.title
                        renamingSpaceID = space.id
                    }
                    Button("Edit Theme…") {
                        browserState.switchToSpace(at: index)
                        browserState.isThemePickerPresented = true
                    }
                    if browserState.spaces.count > 1 {
                        Divider()
                        Button("Delete Space…", role: .destructive) {
                            spacePendingDeletion = space
                        }
                    }
                }
            }
        }
    }
}



// MARK: - Space Switcher Icon

/// Active space: framed with a soft pill background and subtle stroke.
/// Inactive space: displays its icon emoji with subtle opacity and hover highlight.
struct SpaceSwitcherIcon: View {
    let space: AlpSpace
    let isActive: Bool
    let theme: SpaceTheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(space.iconEmoji)
                .font(.system(size: 18))
                .opacity(isActive ? 1.0 : (isHovered ? 1.0 : 0.82))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isActive ? theme.pillBackground : (isHovered ? theme.hoverBackground : Color.clear))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isActive ? theme.pillBorderColor : Color.clear, lineWidth: 0.8)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(space.title)
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
                    // Space title header (e.g. "🧌 Personal")
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
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(currentSpace.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: browserState.spaceTransitionDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: browserState.spaceTransitionDirection > 0 ? .leading : .trailing).combined(with: .opacity)
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .offset(x: gestures.sidebarSwipeOffset)
            .animation(.spring(response: 0.30, dampingFraction: 0.85), value: browserState.activeSpaceID)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Row Views for Tabs and Nodes

struct SidebarNodeRowView: View {
    @EnvironmentObject var browserState: BrowserState
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
                isSelected: browserState.activeTabID == tab.id,
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
    @State private var isTargetedForDrop = false
    @State private var isRenaming = false
    @State private var nameDraft = ""
    @State private var showIconPicker = false

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
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: 14)

                    Group {
                        if let icon = folder.customIcon {
                            AlpCustomIconView(icon: icon, size: 14, tint: theme.effectiveAccentColor)
                        } else {
                            Image(systemName: isExpanded ? "folder.fill" : "folder")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.effectiveAccentColor)
                        }
                    }
                    .alpIconPicker(isPresented: $showIconPicker, current: folder.customIcon) {
                        browserState.setFolderIcon(id: folder.id, to: $0)
                    }

                    Text(folder.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.foregroundColor)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isTargetedForDrop ? theme.effectiveAccentColor : Color.clear, lineWidth: 1.5)
        )
        .contextMenu {
            Button("Rename Folder…") {
                nameDraft = folder.title
                isRenaming = true
            }
            Button("Change Icon…") {
                showIconPicker = true
            }
            Button("Delete Folder (Keep Tabs)", role: .destructive) {
                browserState.deleteFolder(id: folder.id)
            }
        }
        .alert("Rename Folder", isPresented: $isRenaming) {
            TextField("Folder name", text: $nameDraft)
            Button("Rename") { browserState.renameFolder(id: folder.id, to: nameDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .onDrop(of: [UTType.plainText.identifier, UTType.text.identifier], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                guard let uuidString = string as? String, let sourceUUID = UUID(uuidString: uuidString) else { return }
                DispatchQueue.main.async {
                    browserState.moveTabIntoFolder(tabID: sourceUUID, folderID: folder.id)
                }
            }
            return true
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
    @State private var isTargetedForDrop = false
    @State private var showIconPicker = false

    private var isRetained: Bool {
        isPinned || tab.isPinned || browserState.isRetainedMember(tabID: tab.id)
    }

    var body: some View {
        HStack(spacing: 9) {
            // Favicon or Kind Icon
            Group {
                if isRetained, let icon = tab.customIcon {
                    AlpCustomIconView(icon: icon, size: 15, tint: theme.effectiveAccentColor)
                } else if let fav = FaviconCache.shared.favicon(for: tab.urlString) {
                    Image(nsImage: fav)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                } else {
                    switch tab.kind {
                    case .web:
                        Image(systemName: "globe")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryForegroundColor)
                    case .canvas:
                        Image(systemName: "scribble")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.effectiveAccentColor)
                    case .note:
                        Image(systemName: "note.text")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.effectiveAccentColor)
                    }
                }
            }
            .frame(width: 18, height: 18)
            .alpIconPicker(isPresented: $showIconPicker, current: tab.customIcon) {
                browserState.setTabIcon(id: tab.id, to: $0)
            }

            // Title or Renaming TextField
            if renamingTabID == tab.id {
                TextField("Tab Title", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .onSubmit {
                        browserState.mutateTab(id: tab.id) { $0.customTitle = renameDraft }
                        renamingTabID = nil
                    }
            } else {
                Text(tab.displayTitle)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.foregroundColor : theme.foregroundColor.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Audio Playing Indicator
            if tab.isPlayingAudio {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.effectiveAccentColor)
            }

            // Close / Unload Button Behavior:
            // - Active retained tab (isSelected && isRetained): shows minus sign ("minus") to unload to 0 MB snapshot.
            // - Temporary tab (!isRetained): shows close X ("xmark") only when hovered.
            // - Inactive retained tab: shows close X ("xmark") only when hovered.
            let showMinus = isSelected && isRetained
            let showCloseX = isHovered && !showMinus
            if showMinus || showCloseX {
                Button {
                    browserState.handleTabTrailingButtonAction(for: tab)
                } label: {
                    Image(systemName: showMinus ? "minus" : "xmark")
                        .font(.system(size: showMinus ? 10.5 : 9.5, weight: .bold))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(showMinus ? "Unload Tab" : "Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? theme.selectionBackground : (isHovered ? theme.hoverBackground : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isTargetedForDrop ? theme.effectiveAccentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            browserState.selectTab(tab.id)
        }
        .onDrag {
            browserState.sidebarDragTabID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.plainText.identifier, UTType.text.identifier], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                guard let uuidString = string as? String, let sourceUUID = UUID(uuidString: uuidString) else { return }
                DispatchQueue.main.async {
                    if isPinned {
                        if browserState.isRetainedMember(tabID: sourceUUID) {
                            browserState.reorderPinnedNodes(sourceID: sourceUUID, targetID: tab.id)
                        } else {
                            browserState.moveTabToPinned(tabID: sourceUUID)
                            browserState.reorderPinnedNodes(sourceID: sourceUUID, targetID: tab.id)
                        }
                    } else {
                        if browserState.isRetainedMember(tabID: sourceUUID) {
                            browserState.moveTabToToday(tabID: sourceUUID)
                            browserState.reorderTodayTabs(sourceID: sourceUUID, targetID: tab.id)
                        } else {
                            browserState.reorderTodayTabs(sourceID: sourceUUID, targetID: tab.id)
                        }
                    }
                }
            }
            return true
        }
        .contextMenu {
            if tab.kind == .web {
                Button("Add to Favorites") {
                    browserState.toggleFavorite(tabID: tab.id)
                }
            }
            Button(isRetained ? "Move to Active Tabs" : "Pin Tab") {
                browserState.togglePinTab(id: tab.id)
            }
            if tab.hasNavigatedAwayFromPin {
                Button("Back to Pinned Page") {
                    browserState.resetPinnedTabToHome(id: tab.id)
                }
            }
            if tab.kind == .web {
                Button("Open in Split View") {
                    browserState.addSplitPane(withTabID: tab.id)
                }
            }
            Button("Rename Tab") {
                renameDraft = tab.displayTitle
                renamingTabID = tab.id
            }
            if isRetained && tab.kind == .web {
                Button("Change Icon…") {
                    showIconPicker = true
                }
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
    @EnvironmentObject var browserState: BrowserState
    let tab: TabItem
    let isSelected: Bool
    let theme: SpaceTheme
    let onSelect: () -> Void

    @State private var isHovered = false
    @State private var showIconPicker = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? theme.selectionBackground : (isHovered ? theme.hoverBackground : theme.pillBackground.opacity(0.6)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? theme.effectiveAccentColor.opacity(0.8) : theme.pillBorderColor, lineWidth: isSelected ? 1.2 : 0.6)
                    )

                if let icon = tab.customIcon {
                    AlpCustomIconView(icon: icon, size: 21, tint: theme.foregroundColor)
                } else if let fav = FaviconCache.shared.favicon(for: tab.urlString) {
                    Image(nsImage: fav)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.foregroundColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tab.displayTitle)
        .alpIconPicker(isPresented: $showIconPicker, current: tab.customIcon) {
            browserState.setTabIcon(id: tab.id, to: $0)
        }
        .contextMenu {
            Button("Remove from Favorites") {
                browserState.toggleFavorite(tabID: tab.id)
            }
            Button("Change Icon…") {
                showIconPicker = true
            }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.urlString, forType: .string)
            }
            Divider()
            Button("Unload Tab") {
                browserState.handleTabTrailingButtonAction(for: tab)
            }
        }
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
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isHovered ? theme.foregroundColor : theme.secondaryForegroundColor)
                    .frame(width: 18, height: 18)

                Text("New Tab")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isHovered ? theme.foregroundColor : theme.secondaryForegroundColor)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
