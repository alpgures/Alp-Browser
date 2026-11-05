import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
            // 1. Top Window Bar (Traffic Lights Clearance + Navigation Buttons)
            topNavigationRow
                .padding(.top, 8)
                .padding(.horizontal, 12)

            // 2. Arc URL / Command Bar Pill
            urlCommandPill
                .padding(.horizontal, 10)

            // 3. Favorites Grid (Top Apps across Spaces)
            if !browserState.favorites.isEmpty {
                favoritesGrid
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }

            // 4. 120Hz Interactive Two-Finger Horizontal Space Pager (Arc's `SidebarPagingContainerScrollView`)
            SidebarHorizontalPagerView(
                renamingTabID: $renamingTabID,
                renameDraft: $renameDraft
            )

            // 5. Floating Sidebar Media Mini-Player Card (when background tab plays audio/video)
            if let audioTab = browserState.backgroundAudioPlayingTab {
                sidebarMediaMiniPlayer(for: audioTab)
                    .padding(.horizontal, 10)
            }

            // 6. Featherweight Memory Pill
            memoryFooter
                .padding(.horizontal, 10)

            // 7. Bottom Space Switcher & Library Bar
            bottomSpaceSwitcherBar
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .foregroundStyle(theme.foregroundColor)
        .selectTextDisabled()
    }

    // MARK: - 1. Top Navigation Row

    private var topNavigationRow: some View {
        HStack(spacing: 8) {
            if !browserState.isSidebarCollapsed {
                Spacer()
                    .frame(width: 64)
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
            .buttonStyle(ArcIconButtonStyle(theme: theme))
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
            .buttonStyle(ArcIconButtonStyle(theme: theme))
            .disabled(!browserState.canGoBackInActiveTab)
            .help("Back (⌘[ or Two-Finger Swipe Right)")

            Button {
                browserState.goForwardInActiveTab()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .opacity(browserState.canGoForwardInActiveTab ? 1.0 : 0.35)
            }
            .buttonStyle(ArcIconButtonStyle(theme: theme))
            .disabled(!browserState.canGoForwardInActiveTab)
            .help("Forward (⌘] or Two-Finger Swipe Left)")

            Button {
                if let id = browserState.activeTabID {
                    WebViewPool.shared.reload(in: id)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(ArcIconButtonStyle(theme: theme))
            .help("Reload (⌘R)")
        }
    }

    // MARK: - 2. URL Command Pill

    private var urlCommandPill: some View {
        HStack(spacing: 7) {
            // Site Control Center Trigger (Lock / Tune icon on left of URL bar)
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
            .help("Site Control Center (Security, AdBlock, Boosts & Capture)")

            // Clickable Domain / URL Area
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
                browserState.isBoostStudioPresented.toggle()
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.effectiveAccentColor)
            }
            .buttonStyle(.plain)
            .help("Customize Site with Arc Boost")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.pillBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.pillBorderColor, lineWidth: 0.7)
                )
        )
    }

    // MARK: - 3. Favorites Grid

    private var favoritesGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(max(browserState.favorites.count, 2), 4))
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(browserState.favorites) { fav in
                let isSelected = browserState.activeTabID == fav.id
                Button {
                    browserState.selectTab(fav.id)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? theme.selectionBackground : theme.pillBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        isSelected ? theme.foregroundColor.opacity(0.45) : theme.pillBorderColor,
                                        lineWidth: isSelected ? 1.2 : 0.6
                                    )
                            )
                            .frame(height: 38)

                        FaviconBadgeView(tab: fav, size: 18)
                    }
                }
                .buttonStyle(.plain)
                .onDrag {
                    NSItemProvider(object: fav.id.uuidString as NSString)
                }
                .help("\(fav.displayTitle) (\(fav.simplifiedDomain))")
                .contextMenu {
                    tabContextMenu(for: fav)
                }
            }
        }
    }

    // MARK: - 5. Floating Sidebar Media Mini-Player Card

    private func sidebarMediaMiniPlayer(for tab: TabItem) -> some View {
        HStack(spacing: 8) {
            FaviconBadgeView(tab: tab, size: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.displayTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text("Playing Audio • \(tab.simplifiedDomain)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                WebViewPool.shared.toggleMediaPlayback(in: tab.id)
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button {
                let nextMute = !tab.isMuted
                browserState.mutateTab(id: tab.id) { $0.isMuted = nextMute }
                WebViewPool.shared.toggleMuteAudio(in: tab.id, muted: nextMute)
            } label: {
                Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.pillBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.pillBorderColor, lineWidth: 0.7)
                )
        )
        .onTapGesture {
            browserState.selectTab(tab.id)
        }
    }

    // MARK: - 6. Featherweight Memory Footer

    private var memoryFooter: some View {
        HStack(spacing: 6) {
            Text(String(format: "%.0f MB RAM", browserState.currentProcessMemoryMB))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.foregroundColor.opacity(0.85))

            Text("• \(browserState.hibernatedTabsCount) sleeping")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.secondaryForegroundColor)
                .lineLimit(1)

            Spacer()

            Button {
                Task {
                    await browserState.hibernateAllBackgroundTabsNow()
                }
            } label: {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.effectiveAccentColor)
            }
            .buttonStyle(.plain)
            .help("Hibernate all background tabs to 0 MB RAM now")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.hoverBackground)
        )
    }

    // MARK: - 7. Bottom Space Switcher Bar

    private var bottomSpaceSwitcherBar: some View {
        HStack(spacing: 6) {
            Button {
                browserState.isLibrarySheetPresented.toggle()
            } label: {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(ArcIconButtonStyle(theme: theme))
            .help("Open Arc Library (Archive, Easels, Notes, Boosts)")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(browserState.spaces.enumerated()), id: \.element.id) { index, space in
                        let isCurrent = space.id == browserState.activeSpace.id
                        Button {
                            withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 340, damping: 31)) {
                                browserState.switchToSpace(at: index)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(space.iconEmoji)
                                    .font(.system(size: 13))
                                if isCurrent {
                                    Text(space.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, isCurrent ? 9 : 7)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isCurrent ? theme.selectionBackground : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Switch to \(space.title) (⌃\(index + 1) or Two-Finger Swipe on Sidebar)")
                    }
                }
            }

            Spacer(minLength: 2)

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                    browserState.isThemePickerPresented.toggle()
                }
            } label: {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(ArcIconButtonStyle(theme: theme))
            .help("Open Arc Color Scheme Editor")

            Button {
                withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 340, damping: 31)) {
                    browserState.createNewSpace(title: "Space \(browserState.spaces.count + 1)", emoji: "⚡")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(ArcIconButtonStyle(theme: theme))
            .help("New Space")
        }
    }

    @ViewBuilder
    private func tabContextMenu(for tab: TabItem) -> some View {
        Button {
            browserState.addSplitPane(withTabID: tab.id)
        } label: {
            Label("Open in Split View", systemImage: "rectangle.split.2x1")
        }

        Button {
            browserState.openPeek(urlString: tab.urlString, title: tab.displayTitle, sourceTabID: tab.id)
        } label: {
            Label("Preview in Arc Peek", systemImage: "macwindow.on.rectangle")
        }

        Divider()

        Button {
            browserState.toggleFavorite(id: tab.id)
        } label: {
            Label(tab.isFavorite ? "Remove from Favorites" : "Add to Top Favorites", systemImage: "star")
        }

        Button {
            browserState.togglePinTab(id: tab.id)
        } label: {
            Label(tab.isPinned ? "Move to Today Tabs" : "Pin to Space", systemImage: "pin")
        }

        Divider()

        Button {
            Task {
                await WebViewPool.shared.hibernateTab(id: tab.id)
                browserState.mutateTab(id: tab.id) { $0.isHibernated = true }
            }
        } label: {
            Label("Hibernate Tab (0 MB RAM)", systemImage: "moon.zzz")
        }

        Button(role: .destructive) {
            browserState.deletePinnedTabPermanently(id: tab.id)
        } label: {
            Label("Delete Tab", systemImage: "trash")
        }
    }
}

// MARK: - 120Hz Interactive Horizontal Space Pager (Arc's `SidebarPagingContainerScrollView` Equivalent)

private struct SidebarHorizontalPagerView: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject var gestureManager = TrackpadGestureManager.shared

    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String

    var body: some View {
        GeometryReader { geo in
            let pageWidth = max(geo.size.width, 1)
            let activeIndex = browserState.activeSpaceIndex ?? 0

            HStack(spacing: 0) {
                ForEach(browserState.spaces) { space in
                    SidebarSpacePageContentView(
                        space: space,
                        renamingTabID: $renamingTabID,
                        renameDraft: $renameDraft
                    )
                    .frame(width: pageWidth, height: geo.size.height)
                }
            }
            .offset(x: -CGFloat(activeIndex) * pageWidth + gestureManager.sidebarSwipeOffset)
        }
        .clipped()
    }
}

// MARK: - Single Space Page Content (Does NOT Observe `TrackpadGestureManager` -> Zero Re-Render Storms!)

private struct SidebarSpacePageContentView: View {
    @EnvironmentObject var browserState: BrowserState
    let space: ArcSpace
    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String

    @State private var isPinnedDropTargeted = false
    @State private var isTodayDropTargeted = false

    private var theme: SpaceTheme {
        browserState.activeTheme
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                spaceHeaderRow
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 2)

                // Pinned Nodes (Folders + Pinned Tabs)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(space.pinnedNodes) { node in
                        SidebarNodeRow(
                            node: node,
                            depth: 0,
                            renamingTabID: $renamingTabID,
                            renameDraft: $renameDraft
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPinnedDropTargeted ? theme.selectionBackground : Color.clear)
                )
                .onDrop(of: [.text], isTargeted: $isPinnedDropTargeted) { providers in
                    handleDroppedTab(providers: providers, pin: true)
                }

                // Divider between Pinned Tabs and Today Tabs
                pinnedTodayDivider
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)

                // "+ New Tab" Button Row
                newTabButtonRow
                    .padding(.horizontal, 8)

                // Today (Unpinned) Tabs
                todayTabsSection
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isTodayDropTargeted ? theme.selectionBackground : Color.clear)
                    )
                    .onDrop(of: [.text], isTargeted: $isTodayDropTargeted) { providers in
                        handleDroppedTab(providers: providers, pin: false)
                    }
            }
            .padding(.bottom, 12)
        }
    }

    private var spaceHeaderRow: some View {
        HStack(spacing: 7) {
            Text(space.iconEmoji)
                .font(.system(size: 14))

            Text(space.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.foregroundColor)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                    browserState.isThemePickerPresented.toggle()
                }
            } label: {
                Image(systemName: "swatchpalette")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .help("Edit Space Color Scheme")

            Menu {
                Button {
                    browserState.isThemePickerPresented = true
                } label: {
                    Label("Edit Space Color Scheme...", systemImage: "paintpalette")
                }

                Divider()

                Button {
                    browserState.createNewFolder(named: "New Folder")
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    browserState.createNewEasel(title: "\(space.title) Easel")
                } label: {
                    Label("New Easel", systemImage: "scribble.variable")
                }

                Button {
                    browserState.createNewNote(title: "\(space.title) Note")
                } label: {
                    Label("New Note", systemImage: "note.text.badge.plus")
                }

                Divider()

                Button {
                    browserState.tidyTodayTabs()
                } label: {
                    Label("Arc Max: Tidy Today Tabs", systemImage: "wand.and.stars")
                }

                Button {
                    browserState.importFromInstalledArcBrowser()
                } label: {
                    Label("Re-Import from Installed Arc.app", systemImage: "arrow.down.doc")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 22, height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var pinnedTodayDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(theme.foregroundColor.opacity(0.16))
                .frame(height: 1)

            if !space.todayTabs.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        browserState.clearTodayTabs()
                    }
                } label: {
                    Text("Clear")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.secondaryForegroundColor)
                }
                .buttonStyle(.plain)
                .help("Archive all Today tabs")
            }
        }
    }

    private var newTabButtonRow: some View {
        Button {
            browserState.openCommandBar(prefilledWithCurrentURL: false)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .frame(width: 18)

                Text("New Tab")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.secondaryForegroundColor)

                Spacer()

                Text("⌘T")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondaryForegroundColor.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.hoverBackground)
            )
        }
        .buttonStyle(.plain)
    }

    private var todayTabsSection: some View {
        let tabs = space.todayTabs
        let hasCategories = tabs.contains(where: { $0.todayCategory != nil })

        return VStack(alignment: .leading, spacing: 2) {
            if hasCategories {
                let grouped = Dictionary(grouping: tabs, by: { $0.todayCategory ?? "Other" })
                ForEach(grouped.keys.sorted(), id: \.self) { category in
                    Text(category.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                    ForEach(grouped[category] ?? []) { tab in
                        SidebarTabRow(
                            tab: tab,
                            depth: 0,
                            renamingTabID: $renamingTabID,
                            renameDraft: $renameDraft
                        )
                    }
                }
            } else {
                ForEach(tabs) { tab in
                    SidebarTabRow(
                        tab: tab,
                        depth: 0,
                        renamingTabID: $renamingTabID,
                        renameDraft: $renameDraft
                    )
                }
            }
        }
    }

    private func handleDroppedTab(providers: [NSItemProvider], pin: Bool) -> Bool {
        guard let first = providers.first else { return false }
        first.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let str: String?
            if let data = item as? Data {
                str = String(data: data, encoding: .utf8)
            } else {
                str = item as? String
            }
            if let raw = str, let id = UUID(uuidString: raw) {
                Task { @MainActor in
                    if pin {
                        BrowserState.shared.moveTabToPinned(tabID: id)
                    } else {
                        BrowserState.shared.moveTabToToday(tabID: id)
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Recursive Sidebar Node & Tab Row Views

struct SidebarNodeRow: View {
    @EnvironmentObject var browserState: BrowserState
    let node: SidebarNode
    let depth: Int
    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String

    @State private var isDropTargeted = false

    var body: some View {
        switch node {
        case .tab(let tab):
            SidebarTabRow(
                tab: tab,
                depth: depth,
                renamingTabID: $renamingTabID,
                renameDraft: $renameDraft
            )
            .padding(.horizontal, 8)

        case .folder(let folder):
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                        browserState.toggleFolderExpanded(folderID: folder.id)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(browserState.activeTheme.secondaryForegroundColor)
                            .frame(width: 12)

                        Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 12.5))
                            .foregroundStyle(browserState.activeTheme.effectiveAccentColor)

                        Text(folder.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(browserState.activeTheme.foregroundColor.opacity(0.92))
                            .lineLimit(1)

                        Spacer()

                        Text("\(folder.children.count)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(browserState.activeTheme.secondaryForegroundColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(browserState.activeTheme.hoverBackground))
                    }
                    .padding(.leading, CGFloat(depth * 14) + 8)
                    .padding(.trailing, 10)
                    .padding(.vertical, 5.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isDropTargeted ? browserState.activeTheme.selectionBackground : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onDrop(of: [.text], isTargeted: $isDropTargeted) { providers in
                    guard let first = providers.first else { return false }
                    first.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                        let str: String?
                        if let data = item as? Data {
                            str = String(data: data, encoding: .utf8)
                        } else {
                            str = item as? String
                        }
                        if let raw = str, let tabID = UUID(uuidString: raw) {
                            Task { @MainActor in
                                BrowserState.shared.moveTabIntoFolder(tabID: tabID, folderID: folder.id)
                            }
                        }
                    }
                    return true
                }

                if folder.isExpanded {
                    ForEach(folder.children) { child in
                        SidebarNodeRow(
                            node: child,
                            depth: depth + 1,
                            renamingTabID: $renamingTabID,
                            renameDraft: $renameDraft
                        )
                    }
                }
            }
        }
    }
}

struct SidebarTabRow: View {
    @EnvironmentObject var browserState: BrowserState
    let tab: TabItem
    let depth: Int
    @Binding var renamingTabID: UUID?
    @Binding var renameDraft: String

    @State private var isHovered = false

    private var isSelected: Bool {
        browserState.activeTabID == tab.id
    }

    private var isInSplitView: Bool {
        browserState.activeSpace.splitPaneTabIDs.count > 1 && browserState.activeSpace.splitPaneTabIDs.contains(tab.id)
    }

    /// In Arc: only a FOCUSED Pinned Tab shows a minus (`-`) to unload/unfocus it;
    /// any unfocused tab (or any Today tab) shows an X (`×`).
    private var showsMinusButton: Bool {
        tab.isPinned && isSelected
    }

    var body: some View {
        HStack(spacing: 4) {
            // Left Selectable Area (Favicon + Title)
            Button {
                browserState.selectTab(tab.id)
            } label: {
                HStack(spacing: 8) {
                    FaviconBadgeView(tab: tab, size: 16)

                    if renamingTabID == tab.id {
                        TextField("Tab Title", text: $renameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, weight: .medium))
                            .onSubmit {
                                browserState.mutateTab(id: tab.id) {
                                    $0.customTitle = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                                renamingTabID = nil
                                browserState.scheduleSave()
                            }
                    } else {
                        Text(tab.displayTitle)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(
                                isSelected
                                    ? browserState.activeTheme.foregroundColor
                                    : browserState.activeTheme.foregroundColor.opacity(0.86)
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    renameDraft = tab.displayTitle
                    renamingTabID = tab.id
                }
            )

            // Trailing Action Indicators & Buttons (Fixed-geometry layout so hovering never shifts text or triggers tracking-area loops)
            if tab.isPlayingAudio {
                Button {
                    let nextMute = !tab.isMuted
                    browserState.mutateTab(id: tab.id) { $0.isMuted = nextMute }
                    WebViewPool.shared.toggleMuteAudio(in: tab.id, muted: nextMute)
                } label: {
                    Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(browserState.activeTheme.effectiveAccentColor)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(tab.isMuted ? "Unmute Tab" : "Mute Tab")
            }

            if isInSplitView {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(browserState.activeTheme.effectiveAccentColor)
            }

            if tab.hasNavigatedAwayFromPin {
                Button {
                    browserState.resetPinnedTabToHome(id: tab.id)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(browserState.activeTheme.effectiveAccentColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Return to Pinned Home URL")
            }

            // Always keep the trailing button in the layout tree at fixed 20x20 size so hovering never causes layout jitter
            Button {
                browserState.handleTabTrailingButtonAction(for: tab)
            } label: {
                Image(systemName: showsMinusButton ? "minus" : "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(browserState.activeTheme.secondaryForegroundColor)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.0)
            .allowsHitTesting(isHovered)
            .help(showsMinusButton ? "Unload & Unfocus Pinned Tab (⌘W)" : (tab.isPinned ? "Remove Pinned Tab" : "Close Tab (⌘W)"))
        }
        .padding(.leading, CGFloat(depth * 14) + 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? browserState.activeTheme.selectionBackground
                        : (isHovered ? browserState.activeTheme.hoverBackground : Color.clear)
                )
        )
        .transaction { tx in
            tx.animation = nil
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .onDrag {
            NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .contextMenu {
            Button {
                renameDraft = tab.displayTitle
                renamingTabID = tab.id
            } label: {
                Label("Rename Tab...", systemImage: "pencil")
            }

            Button {
                browserState.addSplitPane(withTabID: tab.id)
            } label: {
                Label("Add to Split View", systemImage: "rectangle.split.2x1")
            }

            Button {
                browserState.openPeek(urlString: tab.urlString, title: tab.displayTitle, sourceTabID: tab.id)
            } label: {
                Label("Open in Arc Peek", systemImage: "macwindow.on.rectangle")
            }

            Divider()

            Button {
                browserState.togglePinTab(id: tab.id)
            } label: {
                Label(tab.isPinned ? "Unpin to Today" : "Pin to Space", systemImage: "pin")
            }

            Button {
                browserState.toggleFavorite(id: tab.id)
            } label: {
                Label(tab.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: "star")
            }

            if tab.hasNavigatedAwayFromPin {
                Button {
                    browserState.resetPinnedTabToHome(id: tab.id)
                } label: {
                    Label("Reset to Pinned URL", systemImage: "arrow.uturn.backward")
                }
            }

            Divider()

            Button {
                Task {
                    await WebViewPool.shared.hibernateTab(id: tab.id)
                    browserState.mutateTab(id: tab.id) { $0.isHibernated = true }
                }
            } label: {
                Label("Hibernate Tab (0 MB RAM)", systemImage: "moon.zzz")
            }

            if tab.isPinned {
                Button(role: .destructive) {
                    browserState.deletePinnedTabPermanently(id: tab.id)
                } label: {
                    Label("Delete Pinned Tab", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    browserState.closeTab(id: tab.id)
                } label: {
                    Label("Close Tab", systemImage: "xmark")
                }
            }
        }
    }
}

// MARK: - In-Memory NSCache Favicon Badge & Button Styles

struct FaviconBadgeView: View {
    let tab: TabItem
    let size: CGFloat
    @State private var loadedImage: NSImage?

    var body: some View {
        switch tab.kind {
        case .easel:
            Image(systemName: "scribble.variable")
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: size, height: size)
        case .note:
            Image(systemName: "note.text")
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: size, height: size)
        case .web:
            let img = loadedImage ?? FaviconCache.shared.cachedImage(for: tab.faviconURL)
            if let nsImg = img {
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                monogramFallback
                    .onAppear {
                        FaviconCache.shared.loadImage(for: tab.faviconURL) { fetched in
                            if let fetched = fetched {
                                self.loadedImage = fetched
                            }
                        }
                    }
            }
        }
    }

    private var monogramFallback: some View {
        let letter = String(tab.simplifiedDomain.prefix(1)).uppercased()
        return ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.14))
            Text(letter.isEmpty ? "🌐" : letter)
                .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
        }
        .frame(width: size, height: size)
    }
}

struct ArcIconButtonStyle: ButtonStyle {
    let theme: SpaceTheme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.foregroundColor.opacity(isHovered ? 1.0 : 0.75))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? theme.hoverBackground : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func selectTextDisabled() -> some View {
        self
    }
}
