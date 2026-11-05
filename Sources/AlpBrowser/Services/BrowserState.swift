//
//  BrowserState.swift
//  Alp Browser
//
//  Central state coordinator for spaces, tabs, styles, and browser persistence.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import SwiftUI
import AppKit
import Combine
import Darwin

@MainActor
public final class BrowserState: ObservableObject {
    public static let shared = BrowserState()

    // MARK: - Core Spaces & Sidebar State
    @Published public var spaces: [AlpSpace] = []
    @Published public var favorites: [TabItem] = []
    @Published public var activeSpaceID: UUID?

    // MARK: - UI Chrome & Overlays State
    @Published public var isSidebarCollapsed: Bool = false
    @Published public var isSidebarHoverPeeking: Bool = false
    @Published public var sidebarWidth: CGFloat = 256

    @Published public var isCommandBarPresented: Bool = false
    @Published public var commandBarInitialQuery: String = ""

    @Published public var peekSession: PeekSession?
    @Published public var isFindBarPresented: Bool = false
    @Published public var isStyleStudioPresented: Bool = false
    @Published public var isThemePickerPresented: Bool = false
    @Published public var isLibrarySheetPresented: Bool = false
    @Published public var isSettingsPresented: Bool = false
    @Published public var isSiteControlCenterPresented: Bool = false
    @Published public var selectedLibrarySection: LibrarySection = .archive

    // MARK: - Control + Tab Recent Switcher State
    @Published public var recentTabIDs: [UUID] = []
    @Published public var isTabSwitcherPresented: Bool = false
    @Published public var tabSwitcherSelectedIndex: Int = 0
    @Published public var draggedTabID: UUID?

    // MARK: - Features State (Page Styles, Canvas, Notes, Archive)
    @Published public var styles: [PageMod] = []
    @Published public var canvases: [AlpCanvas] = []
    @Published public var notes: [AlpNote] = []
    @Published public var archivedTabs: [ArchivedTab] = []

    // MARK: - Memory, Settings & App Icon State
    @Published public var autoArchiveHours: Double = 12.0
    @Published public var autoHibernateMinutes: Double = 5.0
    @Published public var adBlockerEnabled: Bool = true
    @Published public var currentProcessMemoryMB: Double = 0.0
    @Published public var syncConfig: AlpSyncConfig = AlpSyncConfig()
    @Published public var syncStatusText: String = "Ready"
    @Published public var isSyncConnected: Bool = false
    @Published public var toastMessage: String?
    @Published public var selectedIconName: String = "alp_browser_original"

    public enum LibrarySection: String, CaseIterable, Identifiable {
        case archive = "Archive"
        case canvas = "Canvas"
        case notes = "Notes"
        case styles = "Styles"
        case sync = "Sync"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .archive: return "archivebox"
            case .canvas: return "scribble.variable"
            case .notes: return "note.text"
            case .styles: return "slider.horizontal.3"
            case .sync: return "arrow.triangle.2.circlepath"
            }
        }
    }

    private var hasImportedFromArc: Bool = false
    private var memoryTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        WebViewPool.shared.browserState = self
        loadPersistedOrImportFromArc()
        startMemoryAndMaintenanceTimers()
        TrackpadGestureManager.shared.startMonitoring()
        Task {
            await refreshSyncStatus()
            await performSilentSync()
        }
    }

    // MARK: - Active Space & Tab Properties

    public var activeSpaceIndex: Int? {
        guard let id = activeSpaceID else { return spaces.indices.first }
        return spaces.firstIndex(where: { $0.id == id }) ?? spaces.indices.first
    }

    public var activeSpace: AlpSpace {
        get {
            if let idx = activeSpaceIndex {
                return spaces[idx]
            }
            return AlpSpace(title: "Personal", iconEmoji: "🧌", theme: .userPersonalSky)
        }
        set {
            if let idx = activeSpaceIndex {
                spaces[idx] = newValue
                scheduleSave()
            }
        }
    }

    public var activeTheme: SpaceTheme {
        activeSpace.theme
    }

    public var activeTabID: UUID? {
        get { activeSpace.activeTabID }
        set {
            guard let idx = activeSpaceIndex else { return }
            spaces[idx].activeTabID = newValue
            if let tabID = newValue {
                markTabActive(tabID)
            }
            scheduleSave()
        }
    }

    public var activeTab: TabItem? {
        guard let id = activeTabID else { return nil }
        return findTab(id: id)
    }

    public var visibleViewportTabIDs: [UUID] {
        let splitIDs = activeSpace.splitPaneTabIDs.filter { findTab(id: $0) != nil }
        if splitIDs.count > 1 {
            return splitIDs
        }
        if let active = activeTabID {
            return [active]
        }
        return []
    }

    public var totalTabsCount: Int {
        favorites.count + spaces.reduce(0) { $0 + $1.allTabs.count }
    }

    public var hibernatedTabsCount: Int {
        let all = favorites + spaces.flatMap { $0.allTabs }
        return all.filter { !WebViewPool.shared.hasLiveWebView(for: $0.id) }.count
    }

    public var backgroundAudioPlayingTab: TabItem? {
        let all = favorites + spaces.flatMap { $0.allTabs }
        return all.first(where: { $0.isPlayingAudio && $0.id != activeTabID })
    }

    // MARK: - Navigation Helpers

    public var canGoBackInActiveTab: Bool {
        guard let id = activeTabID else { return false }
        return WebViewPool.shared.canGoBack(in: id)
    }

    public var canGoForwardInActiveTab: Bool {
        guard let id = activeTabID else { return false }
        return WebViewPool.shared.canGoForward(in: id)
    }

    public func goBackInActiveTab() {
        guard let id = activeTabID else { return }
        WebViewPool.shared.goBack(in: id)
    }

    public func goForwardInActiveTab() {
        guard let id = activeTabID else { return }
        WebViewPool.shared.goForward(in: id)
    }

    // MARK: - Control + Tab Recent Tab Switcher

    public var switcherCandidateTabs: [TabItem] {
        let validRecent = recentTabIDs.compactMap { findTab(id: $0) }
        var combined = validRecent
        for tab in activeSpace.allTabs + favorites {
            if !combined.contains(where: { $0.id == tab.id }) {
                combined.append(tab)
            }
            if combined.count >= 5 { break }
        }
        return Array(combined.prefix(5))
    }

    public func stepTabSwitcher(backwards: Bool) {
        let candidates = switcherCandidateTabs
        guard candidates.count > 1 else { return }
        if !isTabSwitcherPresented {
            isTabSwitcherPresented = true
            tabSwitcherSelectedIndex = backwards ? (candidates.count - 1) : 1
        } else {
            if backwards {
                tabSwitcherSelectedIndex = (tabSwitcherSelectedIndex - 1 + candidates.count) % candidates.count
            } else {
                tabSwitcherSelectedIndex = (tabSwitcherSelectedIndex + 1) % candidates.count
            }
        }
    }

    public func commitTabSwitcherSelection() {
        let candidates = switcherCandidateTabs
        isTabSwitcherPresented = false
        if candidates.indices.contains(tabSwitcherSelectedIndex) {
            selectTab(candidates[tabSwitcherSelectedIndex].id)
        }
    }

    // MARK: - Tab Lookup & Mutators

    public func findTab(id: UUID) -> TabItem? {
        if let fav = favorites.first(where: { $0.id == id }) {
            return fav
        }
        for space in spaces {
            if let today = space.todayTabs.first(where: { $0.id == id }) {
                return today
            }
            if let pinned = findTabInNodes(id: id, nodes: space.pinnedNodes) {
                return pinned
            }
        }
        return nil
    }

    private func findTabInNodes(id: UUID, nodes: [SidebarNode]) -> TabItem? {
        for node in nodes {
            switch node {
            case .tab(let tab):
                if tab.id == id { return tab }
            case .folder(let folder):
                if let found = findTabInNodes(id: id, nodes: folder.children) {
                    return found
                }
            }
        }
        return nil
    }

    public func selectTab(_ tabID: UUID, inSpace spaceID: UUID? = nil) {
        if let sid = spaceID, sid != activeSpaceID {
            activeSpaceID = sid
        } else if findTab(id: tabID)?.isFavorite == false {
            for sp in spaces where sp.allTabs.contains(where: { $0.id == tabID }) {
                if sp.id != activeSpaceID {
                    activeSpaceID = sp.id
                }
                break
            }
        }

        guard let sIdx = activeSpaceIndex else { return }

        if spaces[sIdx].splitPaneTabIDs.count > 1 {
            if !spaces[sIdx].splitPaneTabIDs.contains(tabID) {
                if let oldActive = spaces[sIdx].activeTabID,
                   let paneIdx = spaces[sIdx].splitPaneTabIDs.firstIndex(of: oldActive) {
                    spaces[sIdx].splitPaneTabIDs[paneIdx] = tabID
                } else {
                    spaces[sIdx].splitPaneTabIDs = []
                }
            }
        }

        spaces[sIdx].activeTabID = tabID
        markTabActive(tabID)
        scheduleSave()
    }

    private func markTabActive(_ tabID: UUID) {
        recentTabIDs.removeAll { $0 == tabID }
        recentTabIDs.insert(tabID, at: 0)
        if recentTabIDs.count > 12 {
            recentTabIDs = Array(recentTabIDs.prefix(12))
        }
        mutateTab(id: tabID) { tab in
            tab.isHibernated = false
            tab.lastActiveAt = Date()
        }
    }

    public func mutateTab(id tabID: UUID, transform: (inout TabItem) -> Void) {
        var didModify = false

        if let idx = favorites.firstIndex(where: { $0.id == tabID }) {
            transform(&favorites[idx])
            didModify = true
        }

        for sIdx in spaces.indices {
            if let tIdx = spaces[sIdx].todayTabs.firstIndex(where: { $0.id == tabID }) {
                transform(&spaces[sIdx].todayTabs[tIdx])
                didModify = true
            }
            spaces[sIdx].pinnedNodes = mutateNodeInList(id: tabID, nodes: spaces[sIdx].pinnedNodes, transform: transform)
        }

        if didModify {
            objectWillChange.send()
        }
    }

    private func mutateNodeInList(
        id: UUID,
        nodes: [SidebarNode],
        transform: (inout TabItem) -> Void
    ) -> [SidebarNode] {
        nodes.map { node in
            switch node {
            case .tab(var tab):
                if tab.id == id {
                    transform(&tab)
                }
                return .tab(tab)
            case .folder(var folder):
                folder.children = mutateNodeInList(id: id, nodes: folder.children, transform: transform)
                return .folder(folder)
            }
        }
    }

    // MARK: - Drag and Drop Tab Reordering

    public func moveTabToPinned(tabID: UUID) {
        guard let sIdx = activeSpaceIndex, let tab = findTab(id: tabID), !tab.isPinned else { return }
        spaces[sIdx].todayTabs.removeAll { $0.id == tabID }
        var pinned = tab
        pinned.isPinned = true
        pinned.pinnedURLString = tab.urlString
        spaces[sIdx].pinnedNodes.append(.tab(pinned))
        scheduleSave()
    }

    public func moveTabToToday(tabID: UUID) {
        guard let sIdx = activeSpaceIndex, let tab = findTab(id: tabID), tab.isPinned else { return }
        spaces[sIdx].pinnedNodes = removeNode(id: tabID, from: spaces[sIdx].pinnedNodes)
        var unpinned = tab
        unpinned.isPinned = false
        unpinned.pinnedURLString = nil
        spaces[sIdx].todayTabs.insert(unpinned, at: 0)
        scheduleSave()
    }

    public func moveTabIntoFolder(tabID: UUID, folderID: UUID) {
        guard let sIdx = activeSpaceIndex, let tab = findTab(id: tabID) else { return }
        spaces[sIdx].todayTabs.removeAll { $0.id == tabID }
        spaces[sIdx].pinnedNodes = removeNode(id: tabID, from: spaces[sIdx].pinnedNodes)
        var pinned = tab
        pinned.isPinned = true
        pinned.pinnedURLString = pinned.pinnedURLString ?? tab.urlString
        spaces[sIdx].pinnedNodes = insertTabIntoFolder(tab: pinned, folderID: folderID, nodes: spaces[sIdx].pinnedNodes)
        scheduleSave()
    }

    private func insertTabIntoFolder(tab: TabItem, folderID: UUID, nodes: [SidebarNode]) -> [SidebarNode] {
        nodes.map { node in
            switch node {
            case .tab(let t):
                return .tab(t)
            case .folder(var f):
                if f.id == folderID {
                    f.children.append(.tab(tab))
                    f.isExpanded = true
                } else {
                    f.children = insertTabIntoFolder(tab: tab, folderID: folderID, nodes: f.children)
                }
                return .folder(f)
            }
        }
    }

    // MARK: - Screenshot Capture to Canvas / Clipboard (`⌘⇧2`)

    public func capturePageToCanvasOrClipboard(sendToCanvas: Bool = true) async {
        guard let tabID = activeTabID, let tab = findTab(id: tabID) else { return }
        if let img = await WebViewPool.shared.captureSnapshot(for: tabID) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        }
        if sendToCanvas {
            if canvases.isEmpty {
                createNewCanvas(title: "\(activeSpace.title) Captures")
            } else {
                canvases[0].elements.append(
                    AlpCanvasElement(
                        kind: .webCard,
                        text: "📸 \(tab.displayTitle)\n\(tab.urlString)",
                        urlString: tab.urlString,
                        x: 120,
                        y: 120,
                        width: 280,
                        height: 140,
                        color: activeTheme.primaryColor
                    )
                )
                scheduleSave()
            }
            showToast("Captured snapshot to Canvas & Clipboard")
        } else {
            showToast("Copied snapshot to Clipboard")
        }
    }

    // MARK: - Creating, Navigating & Closing Tabs

    public func openCommandBar(prefilledWithCurrentURL: Bool = false) {
        if prefilledWithCurrentURL, let current = activeTab {
            commandBarInitialQuery = current.urlString
        } else {
            commandBarInitialQuery = ""
        }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            isCommandBarPresented = true
        }
    }

    public func handleCommandBarInput(_ rawInput: String, openInNewTab: Bool = true) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let resolvedURL = resolveInputToURLString(trimmed)
        if openInNewTab || activeTabID == nil {
            openNewTab(urlString: resolvedURL, title: trimmed, inBackground: false)
        } else if let currentID = activeTabID {
            navigateTab(id: currentID, to: resolvedURL)
        }
        isCommandBarPresented = false
    }

    public func resolveInputToURLString(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme) {
            return trimmed
        }
        if !trimmed.contains(" ") && (trimmed.contains(".") || trimmed.hasPrefix("localhost")) {
            return "https://\(trimmed)"
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return "https://www.google.com/search?q=\(encoded)"
    }

    @discardableResult
    public func openNewTab(
        urlString: String,
        title: String? = nil,
        inBackground: Bool = false,
        kind: TabKind = .web
    ) -> TabItem {
        guard let sIdx = activeSpaceIndex else {
            return TabItem(title: title ?? urlString, urlString: urlString, kind: kind)
        }
        let display = title ?? (URL(string: urlString)?.host ?? urlString)
        let newTab = TabItem(
            title: display,
            urlString: urlString,
            isFavorite: false,
            isPinned: false,
            isHibernated: inBackground,
            kind: kind
        )
        spaces[sIdx].todayTabs.insert(newTab, at: 0)
        if !inBackground {
            spaces[sIdx].activeTabID = newTab.id
            markTabActive(newTab.id)
        }
        scheduleSave()
        return newTab
    }

    public func navigateTab(id tabID: UUID, to urlString: String) {
        let resolved = resolveInputToURLString(urlString)
        mutateTab(id: tabID) { tab in
            tab.urlString = resolved
            tab.isHibernated = false
            tab.lastActiveAt = Date()
        }
        WebViewPool.shared.loadURL(resolved, in: tabID)
        scheduleSave()
    }

    public func resetPinnedTabToHome(id tabID: UUID) {
        guard let tab = findTab(id: tabID), let pinnedURL = tab.pinnedURLString else { return }
        navigateTab(id: tabID, to: pinnedURL)
    }

    /// Fixed close action: unfocused pinned tab close removes or archives; Today tab closes immediately.
    public func handleTabTrailingButtonAction(for tab: TabItem) {
        closeTab(id: tab.id)
    }

    public func closeTab(id tabID: UUID) {
        guard let sIdx = activeSpaceIndex else { return }

        if let tab = findTab(id: tabID), !tab.isPinned && !tab.isFavorite {
            archivedTabs.insert(
                ArchivedTab(
                    title: tab.displayTitle,
                    urlString: tab.urlString,
                    spaceTitle: spaces[sIdx].title,
                    reason: "Closed Tab (⌘W)"
                ),
                at: 0
            )
        }

        if let tab = findTab(id: tabID), (tab.isPinned || tab.isFavorite) {
            WebViewPool.shared.destroyWebView(for: tabID)
            mutateTab(id: tabID) { t in
                t.isHibernated = true
                t.isLoading = false
                if let home = t.pinnedURLString {
                    t.urlString = home
                }
            }
            if spaces[sIdx].activeTabID == tabID {
                let fallback = spaces[sIdx].todayTabs.first?.id
                    ?? spaces[sIdx].pinnedNodes.flatMap({ $0.allTabs }).first(where: { $0.id != tabID })?.id
                    ?? favorites.first(where: { $0.id != tabID })?.id
                spaces[sIdx].activeTabID = fallback
            }
            scheduleSave()
            return
        }

        // Remove unpinned Today tab
        WebViewPool.shared.destroyWebView(for: tabID)
        spaces[sIdx].todayTabs.removeAll { $0.id == tabID }
        spaces[sIdx].splitPaneTabIDs.removeAll { $0 == tabID }

        if spaces[sIdx].activeTabID == tabID {
            let nextTabID = spaces[sIdx].todayTabs.first?.id
                ?? spaces[sIdx].pinnedNodes.flatMap({ $0.allTabs }).first?.id
                ?? favorites.first?.id
            spaces[sIdx].activeTabID = nextTabID
            if let next = nextTabID {
                markTabActive(next)
            }
        }
        scheduleSave()
    }

    public func deletePinnedTabPermanently(id tabID: UUID) {
        guard let sIdx = activeSpaceIndex else { return }
        WebViewPool.shared.destroyWebView(for: tabID)
        spaces[sIdx].pinnedNodes = removeNode(id: tabID, from: spaces[sIdx].pinnedNodes)
        favorites.removeAll { $0.id == tabID }
        if spaces[sIdx].activeTabID == tabID {
            spaces[sIdx].activeTabID = spaces[sIdx].todayTabs.first?.id
        }
        scheduleSave()
    }

    private func removeNode(id: UUID, from nodes: [SidebarNode]) -> [SidebarNode] {
        var updated: [SidebarNode] = []
        for node in nodes {
            switch node {
            case .tab(let tab):
                if tab.id != id { updated.append(.tab(tab)) }
            case .folder(var folder):
                folder.children = removeNode(id: id, from: folder.children)
                updated.append(.folder(folder))
            }
        }
        return updated
    }

    public func togglePinTab(id tabID: UUID) {
        guard let tab = findTab(id: tabID) else { return }
        if tab.isPinned {
            moveTabToToday(tabID: tabID)
        } else {
            moveTabToPinned(tabID: tabID)
        }
    }

    // MARK: - Split View Management

    public func addSplitPane(withTabID tabID: UUID? = nil) {
        guard let sIdx = activeSpaceIndex else { return }
        var currentSplit = spaces[sIdx].splitPaneTabIDs
        if currentSplit.isEmpty, let active = spaces[sIdx].activeTabID {
            currentSplit = [active]
        }
        let targetID: UUID
        if let explicitID = tabID {
            targetID = explicitID
        } else {
            let newTab = openNewTab(urlString: "https://www.google.com", inBackground: true)
            targetID = newTab.id
        }
        if !currentSplit.contains(targetID) {
            currentSplit.append(targetID)
        }
        spaces[sIdx].splitPaneTabIDs = currentSplit
        spaces[sIdx].activeTabID = targetID
        scheduleSave()
    }

    public func removeSplitPane() {
        guard let sIdx = activeSpaceIndex else { return }
        spaces[sIdx].splitPaneTabIDs = []
        scheduleSave()
    }

    // MARK: - Quick Peek Management

    public func openPeek(urlString: String, title: String, sourceTabID: UUID? = nil) {
        peekSession = PeekSession(urlString: urlString, title: title, sourceTabID: sourceTabID)
    }

    public func expandPeekToFullTab() {
        guard let session = peekSession else { return }
        let newTab = openNewTab(urlString: session.urlString, title: session.title, inBackground: false)
        peekSession = nil
        selectTab(newTab.id)
    }

    // MARK: - Spaces Switching

    public func switchToSpace(at index: Int) {
        guard spaces.indices.contains(index) else { return }
        activeSpaceID = spaces[index].id
        scheduleSave()
    }

    public func switchToNextSpace(forward: Bool) {
        guard !spaces.isEmpty else { return }
        let currentIdx = activeSpaceIndex ?? 0
        let nextIdx = forward
            ? (currentIdx + 1) % spaces.count
            : (currentIdx - 1 + spaces.count) % spaces.count
        switchToSpace(at: nextIdx)
    }

    // MARK: - Canvas & Notes Management

    public func createNewCanvas(title: String = "Untitled Canvas") {
        let canvas = AlpCanvas(title: title)
        canvases.insert(canvas, at: 0)
        let tab = openNewTab(urlString: "alp://canvas/\(canvas.id)", title: title, inBackground: false, kind: .canvas(canvas.id))
        selectTab(tab.id)
        scheduleSave()
    }

    public func createNewNote(title: String = "Untitled Note") {
        let note = AlpNote(title: title)
        notes.insert(note, at: 0)
        let tab = openNewTab(urlString: "alp://note/\(note.id)", title: title, inBackground: false, kind: .note(note.id))
        selectTab(tab.id)
        scheduleSave()
    }

    // MARK: - Page Styles & Element Zapping

    public func addZappedSelector(_ selector: String, forTabID tabID: UUID) {
        guard let tab = findTab(id: tabID), let host = URL(string: tab.urlString)?.host else { return }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let idx = styles.firstIndex(where: { $0.domain == domain }) {
            if !styles[idx].zappedSelectors.contains(selector) {
                styles[idx].zappedSelectors.append(selector)
                styles[idx].updatedAt = Date()
                WebViewPool.shared.applyStyle(styles[idx], to: tabID)
            }
        } else {
            let newStyle = PageMod(domain: domain, name: "\(domain) Style", zappedSelectors: [selector])
            styles.append(newStyle)
            WebViewPool.shared.applyStyle(newStyle, to: tabID)
        }
        showToast("Hidden element on \(domain)")
        scheduleSave()
    }

    // MARK: - Zero-RAM Tab Hibernation

    public func hibernateAllBackgroundTabsNow() async {
        let activeVisible = Set(visibleViewportTabIDs)
        let allTabs = favorites + spaces.flatMap { $0.allTabs }

        for tab in allTabs where !activeVisible.contains(tab.id) && !tab.isPlayingAudio {
            await WebViewPool.shared.hibernateTab(id: tab.id)
            mutateTab(id: tab.id) { $0.isHibernated = true }
        }
        updateMemoryMetrics()
        showToast("Background tabs hibernated (0 MB RAM)")
    }

    // MARK: - Cloud Sync Management

    public func syncNow(silent: Bool = false) async {
        if !silent { syncStatusText = "Syncing..." }
        let store = buildPersistedStore()
        let result = await AlpSyncService.shared.pushStore(
            store,
            endpoint: syncConfig.syncEndpointURL,
            vaultID: syncConfig.syncVaultID
        )
        switch result {
        case .success:
            syncConfig.lastSyncedAt = Date()
            isSyncConnected = true
            syncStatusText = "Synced"
            if !silent { showToast("Synced vault successfully") }
        case .failure(let err):
            isSyncConnected = false
            syncStatusText = "Sync failed"
            if !silent { showToast("Sync error: \(err)") }
        }
    }

    public func performSilentSync() async {
        guard syncConfig.autoSyncEnabled else { return }
        await syncNow(silent: true)
    }

    public func refreshSyncStatus() async {
        let (online, status) = await AlpSyncService.shared.checkServerHealth(endpoint: syncConfig.syncEndpointURL)
        isSyncConnected = online
        syncStatusText = online ? "Online (\(status))" : "Offline"
    }

    // MARK: - App Icon Single-Click Selection

    public func selectAppIcon(named iconName: String) {
        selectedIconName = iconName
        UserDefaults.standard.set(iconName, forKey: "alp_selected_icon")

        let path = Bundle.main.path(forResource: iconName, ofType: "icns")
            ?? "/Users/alpgures/Documents/antigravity/arc2.0/Icons/\(iconName).icns"

        if FileManager.default.fileExists(atPath: path),
           let iconImg = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = iconImg
        }
        showToast("App icon updated")
        scheduleSave()
    }

    // MARK: - UI Feedback

    public func showToast(_ text: String) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toastMessage == text {
                withAnimation(.easeOut(duration: 0.2)) {
                    self?.toastMessage = nil
                }
            }
        }
    }

    // MARK: - Store Persistence

    private var storeFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AlpBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    private func buildPersistedStore() -> PersistedBrowserStore {
        PersistedBrowserStore(
            spaces: spaces,
            favorites: favorites,
            activeSpaceID: activeSpaceID,
            styles: styles,
            canvases: canvases,
            notes: notes,
            archivedTabs: archivedTabs,
            autoArchiveHours: autoArchiveHours,
            autoHibernateMinutes: autoHibernateMinutes,
            adBlockerEnabled: adBlockerEnabled,
            syncConfig: syncConfig,
            hasImportedFromArc: hasImportedFromArc,
            selectedIconName: selectedIconName
        )
    }

    public func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveImmediately()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    public func saveImmediately() {
        let store = buildPersistedStore()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(store)
            try data.write(to: storeFileURL, options: .atomic)
        } catch {
            print("Failed to save store: \(error)")
        }
    }

    private func loadPersistedOrImportFromArc() {
        if let data = try? Data(contentsOf: storeFileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let store = try? decoder.decode(PersistedBrowserStore.self, from: data) {
                self.spaces = store.spaces
                self.favorites = store.favorites
                self.activeSpaceID = store.activeSpaceID ?? store.spaces.first?.id
                self.styles = store.styles
                self.canvases = store.canvases
                self.notes = store.notes
                self.archivedTabs = store.archivedTabs
                self.autoArchiveHours = store.autoArchiveHours
                self.autoHibernateMinutes = store.autoHibernateMinutes
                self.adBlockerEnabled = store.adBlockerEnabled
                self.syncConfig = store.syncConfig
                self.hasImportedFromArc = store.hasImportedFromArc
                self.selectedIconName = store.selectedIconName
                return
            }
        }

        // Automatic 1-click import from local Arc.app if available
        importFromInstalledArcBrowser()
    }

    public func importFromInstalledArcBrowser() {
        if AlpSidebarImporter.isArcInstalledDataAvailable {
            do {
                let imported = try AlpSidebarImporter.importFromArc()
                self.spaces = imported.spaces
                self.favorites = imported.favorites
                self.activeSpaceID = imported.spaces.first?.id
                self.hasImportedFromArc = true
                scheduleSave()
                showToast("Imported \(imported.totalImportedTabs) tabs across \(imported.spaces.count) spaces")
                return
            } catch {
                print("Sidebar import failed: \(error)")
            }
        }

        // Fallback default spaces
        self.spaces = [
            AlpSpace(title: "Personal", iconEmoji: "🧌", theme: .userPersonalSky),
            AlpSpace(title: "Leisure", iconEmoji: "👹", theme: .userLeisurePlum)
        ]
        self.activeSpaceID = self.spaces.first?.id
        scheduleSave()
    }

    // MARK: - Background Maintenance & Memory Monitoring

    private func startMemoryAndMaintenanceTimers() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMemoryMetrics()
            }
        }
    }

    private func updateMemoryMetrics() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            currentProcessMemoryMB = Double(info.resident_size) / (1024.0 * 1024.0)
        }
    }
}
