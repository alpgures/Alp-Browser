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
                VStack(spacing: 8) {
                    // 1. Top Navigation Row (Seamless with macOS traffic lights)
                    // The row is exactly the band height, flush with the window top, so its centre
                    // is the traffic-light centre line.
                    topNavigationRow
                        .padding(.horizontal, 8)

                    // 2. Command / URL Bar Pill with hover "..." menu
                    urlCommandPill
                        .padding(.horizontal, 8)
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
        .frame(height: AlpTopBarMetrics.bandHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2. Clean URL Command Pill with Hover "..." Button

    private var urlCommandPill: some View {
        HStack(spacing: 6) {
            // Domain / URL Title Area (Click opens Command Bar ⌘T / ⌘L)
            Button {
                browserState.openCommandBar(prefilledWithCurrentURL: true)
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
                            .frame(width: 13, height: 13)
                    }

                    Text(browserState.activeTab.flatMap { $0.isBlank ? nil : $0.simplifiedDomain } ?? "Search or Enter URL...")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(theme.foregroundColor.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Revealable "..." button when hovered over the website bubble
            if isHoveringUrlPill {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                        browserState.isSiteControlCenterPresented.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(theme.hoverBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("Site Controls & Options")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.pillBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(theme.pillBorderColor, lineWidth: 0.8)
                )
        )
        .contentShape(Rectangle())
        .onHover { isHoveringUrlPill = $0 }
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
                .contextMenu {
                    Button("Remove from Favorites") {
                        browserState.toggleFavorite(tabID: tab.id)
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
            HStack(spacing: 4) {
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
            .padding(.horizontal, 68)

            HStack(spacing: 4) {
                // Leading: Library (folder)
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                        browserState.isLibrarySheetPresented = true
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AlpIconButtonStyle(theme: theme))
                .help("Library")

                // Leading: Settings (gearshape)
                Button {
                    browserState.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AlpIconButtonStyle(theme: theme))
                .help("Settings (⌘,)")

                Spacer(minLength: 0)

                // Trailing: "+ ⌵" (New Space / Folder / Easel / Note)
                Menu {
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
                            .font(.system(size: 12.5, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(height: 24)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("New Space…")
            }
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity)
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
                .font(.system(size: 14))
                .opacity(isActive ? 1.0 : (isHovered ? 1.0 : 0.82))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? theme.pillBackground : (isHovered ? theme.hoverBackground : Color.clear))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var isRetained: Bool {
        isPinned || tab.isPinned || browserState.isRetainedMember(tabID: tab.id)
    }

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
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(showMinus ? "Unload Tab" : "Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? theme.selectionBackground : (isHovered ? theme.hoverBackground : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            .frame(maxWidth: .infinity)
            .frame(height: 42)
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
            .frame(maxWidth: .infinity)
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
