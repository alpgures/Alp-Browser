//
//  CommandBarView.swift
//  Alp Browser
//
//  Floating Command Bar (⌘T / ⌘L) with a single-line layout.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit
import Foundation

public struct CommandBarView: View {
    @EnvironmentObject var browserState: BrowserState
    @FocusState private var isInputFocused: Bool

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var keyMonitor: Any?

    private var openInCurrentTab: Bool {
        !browserState.commandBarInitialQuery.isEmpty
    }

    struct CommandSuggestion: Identifiable {
        /// Stable across re-renders so hovering a row does not rebuild the list.
        let id: String
        let icon: String
        let favicon: NSImage?
        let title: String
        let isTabSwitch: Bool
        let isActionRow: Bool
        let shortcutBadge: String?
        let trailingLabel: String?
        let action: () -> Void

        init(
            id: String,
            icon: String,
            favicon: NSImage? = nil,
            title: String,
            isTabSwitch: Bool = false,
            isActionRow: Bool = false,
            shortcutBadge: String? = nil,
            trailingLabel: String? = nil,
            action: @escaping () -> Void
        ) {
            self.id = id
            self.icon = icon
            self.favicon = favicon
            self.title = title
            self.isTabSwitch = isTabSwitch
            self.isActionRow = isActionRow
            self.shortcutBadge = shortcutBadge
            self.trailingLabel = trailingLabel
            self.action = action
        }
    }

    public init() {}

    /// One runnable command (menu action) the bar can offer.
    private struct BarAction {
        let keywords: String
        let icon: String
        let title: String
        var badge: String?
        let run: () -> Void
    }

    /// Everything the menus offer that makes sense from a command bar, limited to what applies right now.
    /// Each action closes the bar first, then runs.
    private func availableActions(query trimmed: String) -> [BarAction] {
        let bs = browserState
        func act(_ keywords: String, _ icon: String, _ title: String, _ badge: String? = nil, _ body: @escaping () -> Void) -> BarAction {
            BarAction(keywords: keywords, icon: icon, title: title, badge: badge, run: {
                bs.isCommandBarPresented = false
                body()
            })
        }
        var list: [BarAction] = []
        let hasTab = bs.activeTab != nil
        let isWebTab = bs.activeTab?.kind == .web

        // Split view
        list.append(act("split view pane side add", "rectangle.split.2x1", "Add Split View", "⌃⇧=") { bs.addSplitPane() })
        if bs.isSplitActive {
            list.append(act("close exit leave split view panes", "rectangle", "Exit Split View") { bs.closeSplitView() })
            list.append(act("close remove split view pane", "rectangle.badge.minus", "Close Split View Pane", "⌃⇧-") { bs.removeSplitPane() })
            list.append(act("rotate switch split view direction vertical horizontal", "rectangle.split.1x2", "Switch Split View Direction", "⌃⇧\\") { bs.toggleSplitOrientation() })
            list.append(act("focus next split view pane", "arrow.right.square", "Focus Next Split Pane", "⌘⌥]") { bs.focusSplitPane(forward: true) })
            list.append(act("focus previous split view pane", "arrow.left.square", "Focus Previous Split Pane", "⌘⌥[") { bs.focusSplitPane(forward: false) })
            list.append(act("move split view pane forward position", "arrow.right.to.line", "Move Split Pane Forward", "⌃⌘]") { bs.moveFocusedSplitPane(forward: true) })
            list.append(act("move split view pane backward position", "arrow.left.to.line", "Move Split Pane Backward", "⌃⌘[") { bs.moveFocusedSplitPane(forward: false) })
        }

        // Current page
        if hasTab {
            if bs.canGoBackInActiveTab {
                list.append(act("back navigate previous page", "chevron.left", "Go Back", "⌘[") { bs.goBackInActiveTab() })
            }
            if bs.canGoForwardInActiveTab {
                list.append(act("forward navigate next page", "chevron.right", "Go Forward", "⌘]") { bs.goForwardInActiveTab() })
            }
            if isWebTab {
                list.append(act("reload refresh page", "arrow.clockwise", "Reload Page", "⌘R") { bs.reloadActiveTab() })
                list.append(act("copy url link address current page", "link", "Copy Current URL", "⌘⇧C") {
                    if let url = bs.activeTab?.urlString {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        bs.showToast("Copied URL to clipboard")
                    }
                })
                list.append(act("find in page search text", "text.magnifyingglass", "Find in Page", "⌘F") { bs.isFindBarPresented = true })
                list.append(act("capture screenshot page easel canvas", "camera.viewfinder", "Capture Page to Easel", "⌘⇧2") {
                    Task { await bs.capturePageToCanvasOrClipboard(sendToCanvas: true) }
                })
                list.append(act("peek preview current page", "eye", "Peek Current Page") {
                    if let tab = bs.activeTab { bs.openPeek(urlString: tab.urlString, title: tab.displayTitle, sourceTabID: tab.id) }
                })
                list.append(act("boost style css zapper customize page site", "wand.and.stars", "Customize Page Style (Boost)", "⌘⇧B") { bs.isStyleStudioPresented = true })
                let isFavorite = bs.activeTab?.isFavorite == true
                list.append(act("favorite favourite bookmark", isFavorite ? "star.slash" : "star", isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                    if let id = bs.activeTabID { bs.toggleFavorite(tabID: id) }
                })
            }
            let isPinned = bs.activeTab?.isPinned == true
            list.append(act("pin unpin keep tab", isPinned ? "pin.slash" : "pin", isPinned ? "Unpin Current Tab" : "Pin Current Tab", "⌘D") {
                if let id = bs.activeTabID { bs.togglePinTab(id: id) }
            })
            list.append(act("close tab", "xmark", "Close Current Tab", "⌘W") {
                if let id = bs.activeTabID { bs.closeTab(id: id) }
            })
        }

        // Tabs and memory
        list.append(act("hibernate sleep background tabs memory ram", "moon.zzz", "Hibernate Background Tabs", "⌘⇧H") {
            Task { await bs.hibernateAllBackgroundTabsNow() }
        })
        list.append(act("mini little window new", "macwindow", "New Mini Alp Window", "⌘⌥N") { MiniAlpWindowController.shared.showWindow() })

        // Spaces and sidebar
        list.append(act("next space forward", "arrow.right.circle", "Next Space", "⌘⌥→") { withAnimation { bs.switchToNextSpace(forward: true) } })
        list.append(act("previous space back", "arrow.left.circle", "Previous Space", "⌘⌥←") { withAnimation { bs.switchToNextSpace(forward: false) } })
        list.append(act("new space create", "plus.square.on.square", "New Space") { withAnimation { _ = bs.createSpace() } })
        list.append(act("new folder create pinned", "folder.badge.plus", "New Folder") { bs.createFolder() })
        list.append(act("sidebar toggle hide show collapse", "sidebar.left", "Toggle Sidebar", "⌘S") {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                bs.isSidebarCollapsed.toggle()
                bs.isSidebarHoverPeeking = false
            }
        })
        list.append(act("theme color gradient space edit", "paintpalette", "Edit Space Theme…") { bs.isThemePickerPresented = true })

        // Library
        list.append(act("library open", "books.vertical", "Open Library") { bs.openLibrary() })
        list.append(act("downloads files library", "arrow.down.circle", "Open Downloads") { bs.openLibrary(section: .downloads) })
        list.append(act("media images videos library", "photo.on.rectangle", "Open Media") { bs.openLibrary(section: .media) })
        list.append(act("archive closed tabs history library", "archivebox", "Open Archive") { bs.openLibrary(section: .archive) })
        list.append(act("boosts styles library", "sparkles", "Open Boosts") { bs.openLibrary(section: .boosts) })
        list.append(act("easels notes library", "square.and.pencil", "Open Easels & Notes") { bs.openLibrary(section: .easels) })
        list.append(act("easel canvas board draw new", "pencil.tip.crop.circle", "New Easel", "⌘⇧E") {
            bs.createNewCanvas(title: trimmed.isEmpty ? "Untitled Easel" : trimmed)
        })
        list.append(act("note markdown text editor new", "note.text", "New Note", "⌘⇧N") {
            bs.createNewNote(title: trimmed.isEmpty ? "Quick Note" : trimmed)
        })

        // App
        list.append(act("sync vault cloud now", "arrow.triangle.2.circlepath", "Sync Vault Now", "⌘⇧Y") { Task { await bs.syncNow() } })
        list.append(act("import spaces arc browser", "square.and.arrow.down", "Import Spaces from Arc") { bs.importFromInstalledArcBrowser() })
        list.append(act("settings preferences extensions", "gearshape", "Open Settings…", "⌘,") { bs.isSettingsPresented = true })
        return list
    }

    private func suggestionList() -> [CommandSuggestion] {
        var list: [CommandSuggestion] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let tokens = lower.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let maxRows = 8

        // 1. Primary URL or Web Search Action when user types
        if !trimmed.isEmpty {
            let isLikelyURL = !trimmed.contains(" ") && (trimmed.contains(".") || trimmed.hasPrefix("http") || trimmed.hasPrefix("localhost") || trimmed.hasPrefix("alp://"))
            list.append(
                CommandSuggestion(
                    id: "input",
                    icon: isLikelyURL ? "globe" : "magnifyingglass",
                    title: trimmed,
                    isTabSwitch: false,
                    isActionRow: false,
                    trailingLabel: isLikelyURL ? "Open Link" : "Search Google",
                    action: {
                        browserState.handleCommandBarInput(trimmed, openInNewTab: !openInCurrentTab)
                    }
                )
            )
        }

        // Typing an address also offers to preview it in a Peek instead of opening a tab.
        if !trimmed.isEmpty, !trimmed.contains(" "), trimmed.contains("."), !trimmed.hasPrefix("alp://") {
            list.append(
                CommandSuggestion(
                    id: "peek-input",
                    icon: "eye",
                    title: trimmed,
                    isActionRow: true,
                    trailingLabel: "Open in Peek",
                    action: {
                        browserState.isCommandBarPresented = false
                        browserState.openPeek(urlString: browserState.resolveInputToURLString(trimmed), title: trimmed)
                    }
                )
            )
        }

        // 2. Open / Pinned Tabs Matching Query ("Switch to Tab") — single-line, skipping extension new-tab placeholders
        var seenTabIDs = Set<UUID>()
        var seenTitles = Set<String>()
        let candidateTabs = (browserState.activeSpace.todayTabs + browserState.activeSpace.pinnedNodes.flatMap { $0.allTabs } + browserState.favorites + browserState.spaces.flatMap { $0.allTabs })
        let tabLimit = trimmed.isEmpty ? 4 : 3
        var tabRows = 0
        for tab in candidateTabs {
            guard tabRows < tabLimit else { break }
            guard !seenTabIDs.contains(tab.id) else { continue }
            seenTabIDs.insert(tab.id)

            let urlLower = tab.urlString.lowercased()
            if urlLower.hasPrefix("chrome-extension://") || urlLower == "about:blank" {
                continue
            }
            let title = tab.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty || title.lowercased() == "new tab" {
                continue
            }
            guard !seenTitles.contains(title.lowercased()) else { continue }

            if !tokens.isEmpty {
                let haystack = title.lowercased() + " " + urlLower
                guard tokens.allSatisfy({ haystack.contains($0) }) else { continue }
            }

            seenTitles.insert(title.lowercased())
            let fav: NSImage? = tab.kind == .web ? FaviconCache.shared.favicon(for: tab.urlString) : nil
            let icon: String
            switch tab.kind {
            case .web: icon = "globe"
            case .canvas: icon = "scribble"
            case .note: icon = "note.text"
            }
            list.append(
                CommandSuggestion(
                    id: "tab-\(tab.id.uuidString)",
                    icon: icon,
                    favicon: fav,
                    title: title,
                    isTabSwitch: true,
                    action: {
                        browserState.selectTab(tab.id)
                        browserState.isCommandBarPresented = false
                    }
                )
            )
            tabRows += 1
        }

        // 3. Switch space (typing only): a space whose name matches, or the word "space" plus part of a name
        if !tokens.isEmpty {
            var spaceRows = 0
            for (index, space) in browserState.spaces.enumerated() where space.id != browserState.activeSpaceID {
                guard spaceRows < 2 else { break }
                let haystack = "space " + space.title.lowercased()
                guard tokens.allSatisfy({ haystack.contains($0) }) else { continue }
                spaceRows += 1
                list.append(
                    CommandSuggestion(
                        id: "space-\(space.id.uuidString)",
                        icon: "square.3.layers.3d",
                        title: "\(space.iconEmoji) \(space.title)",
                        isTabSwitch: true,
                        trailingLabel: "Switch to Space",
                        action: {
                            browserState.isCommandBarPresented = false
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                                browserState.switchToSpace(at: index)
                            }
                        }
                    )
                )
            }
        }

        // 4. Actions: one subtle row when the query is empty, every matching action when typing
        let actions = availableActions(query: trimmed)
        if tokens.isEmpty {
            if let first = actions.first {
                list.append(
                    CommandSuggestion(id: "action-\(first.title)", icon: first.icon, title: first.title, isActionRow: true, action: first.run)
                )
            }
        } else {
            for act in actions {
                guard list.count < maxRows else { break }
                let haystack = act.keywords + " " + act.title.lowercased()
                guard tokens.allSatisfy({ haystack.contains($0) }) else { continue }
                list.append(
                    CommandSuggestion(
                        id: "action-\(act.title)",
                        icon: act.icon,
                        title: act.title,
                        isActionRow: true,
                        shortcutBadge: act.badge,
                        action: act.run
                    )
                )
            }
        }

        return Array(list.prefix(maxRows))
    }

    private var suggestions: [CommandSuggestion] { suggestionList() }

    /// Selection bar color derived from the active space theme (a muted slate-teal highlight)
    private var selectionBarColor: Color {
        let p = browserState.activeTheme.primaryColor
        let blended = p.darkened(by: 0.35).blended(with: RGBAColor(red: 0.21, green: 0.45, blue: 0.52), fraction: 0.55)
        return blended.swiftUIColor
    }

    public var body: some View {
        barContent(items: suggestions)   // built once per render, not once per use
    }

    private func barContent(items: [CommandSuggestion]) -> some View {
        ZStack {
            // Transparent backdrop: does NOT dim screen, clicking outside dismisses
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    browserState.isCommandBarPresented = false
                }

            GeometryReader { geo in
            VStack(spacing: 0) {
                // Top input row: leading glyph + large borderless field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)

                    TextField("Search or Enter URL…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white)
                        .focused($isInputFocused)
                        .onChange(of: query) { _, _ in
                            selectedIndex = 0
                        }
                        .onKeyPress(.escape) {
                            browserState.isCommandBarPresented = false
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            if selectedIndex > 0 {
                                selectedIndex -= 1
                            }
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            if selectedIndex < suggestions.count - 1 {
                                selectedIndex += 1
                            }
                            return .handled
                        }
                        .onSubmit {
                            executeSelectedOrSubmit()
                        }

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)

                if !items.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.bottom, 8)
                }

                // Single-line Suggestion Rows (No divider line, fits all rows cleanly without clipping)
                if !items.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let isSelected = (index == selectedIndex)
                            Button {
                                item.action()
                            } label: {
                                HStack(spacing: 11) {
                                    // Leading Icon / Favicon Badge (20x20 rounded square on selected/action rows)
                                    suggestionIconView(for: item, isSelected: isSelected)

                                    Text(item.title)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(isSelected ? .white : .white.opacity(0.84))
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer(minLength: 12)

                                    // Trailing "Switch to Tab [→]" or Shortcut Badge
                                    if item.isTabSwitch || item.trailingLabel != nil {
                                        HStack(spacing: 8) {
                                            Text(item.trailingLabel ?? "Switch to Tab")
                                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))

                                            Image(systemName: item.isTabSwitch ? "arrow.right" : "return")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(isSelected ? selectionBarColor : .white.opacity(0.65))
                                                .frame(width: 19, height: 19)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                                        .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                                                )
                                        }
                                    } else if let badge = item.shortcutBadge {
                                        Text(badge)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(isSelected ? .white : .white.opacity(0.48))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2.5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                                    .fill(Color.white.opacity(isSelected ? 0.22 : 0.08))
                                            )
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(isSelected ? selectionBarColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    selectedIndex = index
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
            .frame(width: 620)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.62))
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(browserState.activeTheme.primaryColor.swiftUIColor.opacity(0.10))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 32, y: 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Sits roughly a quarter of the way down the window, not glued to the top edge.
            .padding(.top, max(150, geo.size.height * 0.24))
            }
        }
        .onExitCommand {
            browserState.isCommandBarPresented = false
        }
        .onAppear {
            query = browserState.commandBarInitialQuery
            isInputFocused = true
            selectedIndex = 0

            // ⌘L pre-fills the current URL; select it so typing replaces it.
            if !browserState.commandBarInitialQuery.isEmpty {
                DispatchQueue.main.async {
                    (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
                }
            }

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC key
                    browserState.isCommandBarPresented = false
                    return nil
                }
                if event.keyCode == 126 { // UP ARROW
                    if selectedIndex > 0 {
                        selectedIndex -= 1
                    }
                    return nil
                }
                if event.keyCode == 125 { // DOWN ARROW
                    if selectedIndex < suggestions.count - 1 {
                        selectedIndex += 1
                    }
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    @ViewBuilder
    private func suggestionIconView(for item: CommandSuggestion, isSelected: Bool) -> some View {
        if let fav = item.favicon {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                }
                Image(nsImage: fav)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: isSelected ? 14 : 15, height: isSelected ? 14 : 15)
            }
            .frame(width: 20, height: 20)
        } else if item.isActionRow {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.22 : 0.08))
                    .frame(width: 20, height: 20)
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
            }
            .frame(width: 20, height: 20)
        } else {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                }
                Image(systemName: item.icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isSelected ? selectionBarColor : .white.opacity(0.60))
            }
            .frame(width: 20, height: 20)
        }
    }

    private func executeSelectedOrSubmit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if suggestions.indices.contains(selectedIndex) {
            suggestions[selectedIndex].action()
        } else if !trimmed.isEmpty {
            browserState.handleCommandBarInput(trimmed, openInNewTab: !openInCurrentTab)
        } else {
            browserState.isCommandBarPresented = false
        }
    }
}
