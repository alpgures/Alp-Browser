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
    @Published public var spaceTransitionDirection: Int = 1

    // MARK: - UI Chrome & Overlays State
    @Published public var isSidebarCollapsed: Bool = false
    @Published public var isSidebarHoverPeeking: Bool = false
    @Published public var sidebarWidth: CGFloat = 296

    @Published public var isCommandBarPresented: Bool = false {
        // Whatever dismisses the bar, the next presentation starts as the centered bar unless the URL dropdown asks otherwise.
        didSet { if !isCommandBarPresented { commandBarAnchored = false } }
    }
    /// True while the bar is shown as the small dropdown under the URL pill (navigates the existing tab) rather than centered.
    @Published public var commandBarAnchored: Bool = false
    @Published public var commandBarInitialQuery: String = ""
    /// Bumped on every openCommandBar call so an already-visible bar can re-take keyboard focus.
    @Published public var commandBarOpenCount: Int = 0

    @Published public var peekSession: PeekSession?
    @Published public var isFindBarPresented: Bool = false
    @Published public var isStyleStudioPresented: Bool = false
    @Published public var isThemePickerPresented: Bool = false
    @Published public var isLibrarySheetPresented: Bool = false
    @Published public var isSettingsPresented: Bool = false
    /// Which quit card is up, if any. The app delegate owns the decision; this only drives the view.
    public enum QuitPrompt { case downloads, confirmation }
    @Published public var quitPrompt: QuitPrompt?
    /// Settings toggle. Kept in UserDefaults (not the sidebar store) so it applies before any state has loaded.
    @Published public var warnBeforeQuitting: Bool = UserDefaults.standard.object(forKey: "alp_warn_before_quitting") as? Bool ?? true {
        didSet { UserDefaults.standard.set(warnBeforeQuitting, forKey: "alp_warn_before_quitting") }
    }
    /// Tabs and spaces named on the quit card: Today tabs plus favorites; pinned tabs are not "open".
    public var quitSummary: (tabs: Int, spaces: Int) {
        (spaces.reduce(favorites.count) { $0 + $1.todayTabs.count }, spaces.count)
    }
    @Published public var isSiteControlCenterPresented: Bool = false
    /// Section the Library should show when it next appears (set by `openLibrary`, consumed by the view).
    public var requestedLibrarySection: LibraryRailSection?

    // MARK: - Control + Tab Recent Switcher State
    @Published public var recentTabIDs: [UUID] = []
    @Published public var isTabSwitcherPresented: Bool = false
    @Published public var tabSwitcherSelectedIndex: Int = 0
    @Published public var draggedTabID: UUID?
    @Published public var splitRatio: CGFloat = 0.5
    /// Tab being dragged out of the sidebar right now. Not @Published: only the split-pane drop targets read it.
    public var sidebarDragTabID: UUID?

    // MARK: - Features State (Page Styles, Canvas, Notes, Archive)
    @Published public var styles: [PageMod] = []
    @Published public var canvases: [AlpCanvas] = []
    @Published public var notes: [AlpNote] = []
    @Published public var archivedTabs: [ArchivedTab] = []

    // MARK: - Memory, Settings & App Icon State
    @Published public var autoArchiveHours: Double = 12.0
    @Published public var autoHibernateMinutes: Double = 5.0
    @Published public var adBlockerEnabled: Bool = true
    /// Not @Published: nothing displays it, and publishing it re-rendered the whole UI on every sample.
    public var currentProcessMemoryMB: Double = 0.0
    @Published public var syncConfig: AlpSyncConfig = AlpSyncConfig()
    @Published public var syncStatusText: String = "Ready"
    @Published public var isSyncConnected: Bool = false
    /// Plain-language reason the last sync or restore did not work; nil when it did. Shown in Settings.
    @Published public var syncProblem: String?
    /// True when the cloud vault was changed on another device and this one stopped before overwriting it.
    @Published public var syncHasConflict: Bool = false
    private var isSyncInFlight = false
    /// Fingerprint of the content (not the sync timestamp) last uploaded or downloaded by this run; nil until one succeeds.
    /// Background syncs compare against it so they only upload when something actually changed.
    private var lastSyncedFingerprint: String?
    private var lastAutoSyncAttempt: Date?
    private var syncDebounceTask: Task<Void, Never>?
    private var periodicSyncTimer: Timer?
    /// Quiet time after the last change before a background sync runs.
    nonisolated private static let syncDebounceSeconds: TimeInterval = 30
    /// Shortest gap between two background attempts, so a failing server is not retried on every edit.
    private static let minAutoSyncGapSeconds: TimeInterval = 60
    /// Background sync interval (a safety net for changes that did not go through `scheduleSave`).
    private static let periodicSyncSeconds: TimeInterval = 600
    @Published public var toastMessage: String?
    @Published public var selectedIconName: String = "alp_browser_original"
    @Published public var customIconConfig: CustomIconConfig = CustomIconConfig()

    private var hasImportedFromArc: Bool = false
    private var memoryTimer: Timer?
    private var hibernateTimer: Timer?
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
        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: Self.periodicSyncSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.autoSyncIfChanged()
            }
        }
        periodicSyncTimer?.tolerance = 60
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

    public func reloadActiveTab() {
        guard let id = activeTabID else { return }
        WebViewPool.shared.reload(in: id)
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
        // A peek belongs to the page it was opened from; choosing another tab dismisses it.
        if peekSession != nil { peekSession = nil }
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

    public func reorderTodayTabs(sourceID: UUID, targetID: UUID) {
        guard let sIdx = activeSpaceIndex, sourceID != targetID else { return }
        var list = spaces[sIdx].todayTabs
        guard let sourceIndex = list.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = list.firstIndex(where: { $0.id == targetID }) else { return }
        let item = list.remove(at: sourceIndex)
        list.insert(item, at: targetIndex)
        spaces[sIdx].todayTabs = list
        scheduleSave()
    }

    public func reorderPinnedNodes(sourceID: UUID, targetID: UUID) {
        guard let sIdx = activeSpaceIndex, sourceID != targetID else { return }
        var list = spaces[sIdx].pinnedNodes
        guard let sourceIndex = list.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = list.firstIndex(where: { $0.id == targetID }) else { return }
        let item = list.remove(at: sourceIndex)
        list.insert(item, at: targetIndex)
        spaces[sIdx].pinnedNodes = list
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

    public func toggleFolderExpanded(folderID: UUID) {
        guard let sIdx = activeSpaceIndex else { return }
        spaces[sIdx].pinnedNodes = toggleFolder(in: spaces[sIdx].pinnedNodes, folderID: folderID)
        scheduleSave()
    }

    private func toggleFolder(in nodes: [SidebarNode], folderID: UUID) -> [SidebarNode] {
        nodes.map { node in
            switch node {
            case .tab:
                return node
            case .folder(var f):
                if f.id == folderID {
                    f.isExpanded.toggle()
                } else {
                    f.children = toggleFolder(in: f.children, folderID: folderID)
                }
                return .folder(f)
            }
        }
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
        guard let tabID = activeTabID, let tab = findTab(id: tabID), tab.kind == .web else { return }
        guard let img = await WebViewPool.shared.captureSnapshot(for: tabID) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])

        guard sendToCanvas else {
            showToast("Copied snapshot to Clipboard")
            return
        }

        // Capture into the most recently updated easel, creating one (without switching tabs) if none exists.
        if canvases.isEmpty {
            canvases.insert(AlpCanvas(title: "\(activeSpace.title) Captures"), at: 0)
        }
        let target = canvases.indices.max(by: { canvases[$0].updatedAt < canvases[$1].updatedAt }) ?? 0
        let count = Double(canvases[target].elements.count)
        if let path = Self.saveCanvasImage(img) {
            canvases[target].elements.append(
                AlpCanvasElement(
                    kind: .image,
                    text: tab.displayTitle,
                    urlString: path,
                    x: 120 + (count * 28).truncatingRemainder(dividingBy: 380),
                    y: 120 + (count * 24).truncatingRemainder(dividingBy: 260),
                    width: 300,
                    height: 220,
                    color: RGBAColor(red: 0.15, green: 0.15, blue: 0.18)
                )
            )
        }
        canvases[target].elements.append(
            AlpCanvasElement(
                kind: .webCard,
                text: "\(tab.displayTitle)\n\(tab.urlString)",
                urlString: tab.urlString,
                x: 120 + (count * 28).truncatingRemainder(dividingBy: 380),
                y: 260 + (count * 24).truncatingRemainder(dividingBy: 200),
                width: 280,
                height: 100,
                color: activeTheme.primaryColor
            )
        )
        canvases[target].updatedAt = Date()
        scheduleSave()
        showToast("Captured to \(canvases[target].title)")
    }

    // MARK: - Easel image storage

    /// Easel images live inside the app's own support folder so they survive the source file moving.
    private static var canvasImagesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AlpBrowser/CanvasImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a snapshot as PNG into the easel image folder and returns its path.
    static func saveCanvasImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = canvasImagesDirectory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try png.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    /// Copies a user-picked image into the easel image folder and returns the copy's path.
    static func importCanvasImage(from source: URL) -> String? {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let dest = canvasImagesDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return dest.path
        } catch {
            return nil
        }
    }

    // MARK: - Creating, Navigating & Closing Tabs

    public func openCommandBar(prefilledWithCurrentURL: Bool = false) {
        if prefilledWithCurrentURL, let current = activeTab {
            commandBarInitialQuery = current.urlString
        } else {
            commandBarInitialQuery = ""
        }
        commandBarOpenCount &+= 1
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            isCommandBarPresented = true
        }
    }

    /// URL-pill click: on an existing page this opens the small dropdown under the pill (editing that tab's URL in place).
    /// A blank tab has nothing to edit, so it gets the centered new-tab command bar.
    public func openURLDropdown() {
        guard let tab = activeTab, tab.kind == .web, !tab.isBlank else {
            openCommandBar(prefilledWithCurrentURL: false)
            return
        }
        commandBarInitialQuery = tab.urlString
        commandBarOpenCount &+= 1
        commandBarAnchored = true
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            isCommandBarPresented = true
        }
    }

    public func handleCommandBarInput(_ rawInput: String, openInNewTab: Bool = true) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("alp://") {
            isCommandBarPresented = false
            let command = trimmed.replacingOccurrences(of: "alp://", with: "").lowercased()
            switch command {
            case "settings", "preferences", "extensions":
                isSettingsPresented = true
                return
            case "library", "archive", "downloads", "canvases", "notes":
                switch command {
                case "archive": openLibrary(section: .archive)
                case "downloads": openLibrary(section: .downloads)
                case "canvases": openLibrary(section: .easels)
                case "notes": openLibrary(section: .notes)
                default: openLibrary()
                }
                return
            case "theme", "themes":
                isThemePickerPresented = true
                return
            case "style", "styles", "boost":
                isStyleStudioPresented = true
                return
            default:
                break
            }
        }

        // chrome:// pages that have a native equivalent open the matching panel.
        if trimmed.lowercased().hasPrefix("chrome://") {
            let page = trimmed.dropFirst("chrome://".count).split(separator: "/").first.map { $0.lowercased() } ?? ""
            isCommandBarPresented = false
            switch page {
            case "settings", "extensions", "flags", "version":
                isSettingsPresented = true
            case "downloads":
                openLibrary(section: .downloads)
            case "history", "bookmarks":
                openLibrary(section: .archive)
            default:
                isSettingsPresented = true
            }
            return
        }

        let resolvedURL = resolveInputToURLString(trimmed)
        // A blank tab is filled in place rather than leaving an empty tab behind.
        if (openInNewTab && activeTab?.isBlank != true) || activeTabID == nil {
            openNewTab(urlString: resolvedURL, title: trimmed, inBackground: false)
        } else if let currentID = activeTabID {
            navigateTab(id: currentID, to: resolvedURL)
        }
        isCommandBarPresented = false
    }

    public func resolveInputToURLString(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about", "alp"].contains(scheme) {
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
        // A blank new tab has nothing to show: the command bar opens over it, as with ⌘T.
        if newTab.isBlank && !inBackground && kind == .web {
            openCommandBar(prefilledWithCurrentURL: false)
        }
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

    /// Returns true if a tab belongs to the sidebar's retained members (favorites, top pinned tabs, or pinned folder items).
    public func isRetainedMember(tabID: UUID) -> Bool {
        if favorites.contains(where: { $0.id == tabID }) { return true }
        for space in spaces {
            if space.pinnedNodes.contains(where: { $0.allTabs.contains(where: { $0.id == tabID }) }) {
                return true
            }
        }
        if let tab = findTab(id: tabID), tab.isPinned {
            return true
        }
        return false
    }

    /// Trailing action on tab row:
    /// - For retained / pinned tabs: hibernates WebView to 0 MB memory snapshot and deselects.
    /// - For temporary tabs: closes and removes the tab immediately.
    public func handleTabTrailingButtonAction(for tab: TabItem) {
        if isRetainedMember(tabID: tab.id) {
            WebViewPool.shared.hibernateTab(id: tab.id)
            mutateTab(id: tab.id) { $0.isHibernated = true; $0.isLoading = false }
            if let sIdx = activeSpaceIndex {
                // A hibernated tab cannot stay on screen as a split pane.
                spaces[sIdx].splitPaneTabIDs.removeAll { $0 == tab.id }
                pruneSplit(at: sIdx)
                if spaces[sIdx].activeTabID == tab.id {
                    spaces[sIdx].activeTabID = spaces[sIdx].todayTabs.first?.id
                }
            }
            scheduleSave()
        } else {
            closeTab(id: tab.id)
        }
    }

    public func closeTab(id tabID: UUID) {
        guard let sIdx = activeSpaceIndex else { return }

        if let tab = findTab(id: tabID), !tab.isPinned && !tab.isFavorite, tab.kind == .web {
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
            spaces[sIdx].splitPaneTabIDs.removeAll { $0 == tabID }
            pruneSplit(at: sIdx)
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
        WebViewPool.shared.forgetTab(tabID)
        spaces[sIdx].todayTabs.removeAll { $0.id == tabID }
        spaces[sIdx].splitPaneTabIDs.removeAll { $0 == tabID }
        pruneSplit(at: sIdx)

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
        WebViewPool.shared.forgetTab(tabID)
        spaces[sIdx].pinnedNodes = removeNode(id: tabID, from: spaces[sIdx].pinnedNodes)
        favorites.removeAll { $0.id == tabID }
        spaces[sIdx].splitPaneTabIDs.removeAll { $0 == tabID }
        pruneSplit(at: sIdx)
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

    /// Opens the Library in the sidebar, optionally on a given section. Reveals the sidebar if it was collapsed.
    public func openLibrary(section: LibraryRailSection? = nil) {
        requestedLibrarySection = section
        isSidebarCollapsed = false
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            isLibrarySheetPresented = true
        }
    }

    // MARK: - Favorites, Folders, Spaces and Archive upkeep

    /// Takes a tab out of whichever container holds it (favorites, a space's pinned tree or Today list) without touching its web view.
    private func detachTab(id tabID: UUID) {
        favorites.removeAll { $0.id == tabID }
        for sIdx in spaces.indices {
            spaces[sIdx].todayTabs.removeAll { $0.id == tabID }
            spaces[sIdx].pinnedNodes = removeNode(id: tabID, from: spaces[sIdx].pinnedNodes)
        }
    }

    /// Adds a tab to the favorites grid, or takes it back out into the active space's Today list.
    public func toggleFavorite(tabID: UUID) {
        guard let sIdx = activeSpaceIndex, var tab = findTab(id: tabID), tab.kind == .web else { return }
        detachTab(id: tabID)
        if tab.isFavorite {
            tab.isFavorite = false
            tab.isPinned = false
            tab.pinnedURLString = nil
            spaces[sIdx].todayTabs.insert(tab, at: 0)
        } else {
            tab.isFavorite = true
            tab.isPinned = true
            tab.pinnedURLString = tab.pinnedURLString ?? tab.urlString
            favorites.append(tab)
        }
        scheduleSave()
    }

    /// New empty folder at the end of the active space's pinned tree.
    @discardableResult
    public func createFolder(title: String = "New Folder") -> UUID? {
        guard let sIdx = activeSpaceIndex else { return nil }
        let folder = FolderItem(title: title, isExpanded: true)
        spaces[sIdx].pinnedNodes.append(.folder(folder))
        scheduleSave()
        return folder.id
    }

    private func updateFolder(id folderID: UUID, in nodes: [SidebarNode], _ transform: (inout FolderItem) -> Void) -> [SidebarNode] {
        nodes.map { (node: SidebarNode) -> SidebarNode in
            guard case .folder(var folder) = node else { return node }
            if folder.id == folderID {
                transform(&folder)
            } else {
                folder.children = updateFolder(id: folderID, in: folder.children, transform)
            }
            return .folder(folder)
        }
    }

    public func renameFolder(id folderID: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sIdx = activeSpaceIndex, !trimmed.isEmpty else { return }
        spaces[sIdx].pinnedNodes = updateFolder(id: folderID, in: spaces[sIdx].pinnedNodes) { $0.title = String(trimmed.prefix(120)) }
        scheduleSave()
    }

    /// Sets (or clears, with nil) a folder's custom icon. Folders live in the pinned tree of whichever space holds them.
    public func setFolderIcon(id folderID: UUID, to icon: AlpCustomIcon?) {
        for sIdx in spaces.indices {
            spaces[sIdx].pinnedNodes = updateFolder(id: folderID, in: spaces[sIdx].pinnedNodes) { $0.customIcon = icon }
        }
        scheduleSave()
    }

    /// Sets (or clears, with nil) the custom icon of a tab. Used for pinned tabs and favorites.
    public func setTabIcon(id tabID: UUID, to icon: AlpCustomIcon?) {
        mutateTab(id: tabID) { $0.customIcon = icon }
        scheduleSave()
    }

    private func dissolveFolder(id folderID: UUID, in nodes: [SidebarNode]) -> [SidebarNode] {
        var result: [SidebarNode] = []
        for node in nodes {
            guard case .folder(var folder) = node else { result.append(node); continue }
            if folder.id == folderID {
                result.append(contentsOf: folder.children)   // its tabs stay pinned, in place
            } else {
                folder.children = dissolveFolder(id: folderID, in: folder.children)
                result.append(.folder(folder))
            }
        }
        return result
    }

    /// Removes a folder but keeps its tabs: they take the folder's place in the pinned list.
    public func deleteFolder(id folderID: UUID) {
        guard let sIdx = activeSpaceIndex else { return }
        spaces[sIdx].pinnedNodes = dissolveFolder(id: folderID, in: spaces[sIdx].pinnedNodes)
        scheduleSave()
    }

    /// Adds a space and switches to it.
    @discardableResult
    public func createSpace() -> UUID {
        let space = AlpSpace(title: "Space \(spaces.count + 1)", iconEmoji: "🪐", theme: .auroraMesh)
        spaces.append(space)
        switchToSpace(at: spaces.count - 1)
        return space.id
    }

    public func renameSpace(id spaceID: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[idx].title = String(trimmed.prefix(80))
        scheduleSave()
    }

    /// Deletes a space (never the last one). Its open web tabs go to the Archive first so nothing is lost silently;
    /// pinned tabs and folders in it are removed with it.
    public func deleteSpace(id spaceID: UUID) {
        guard spaces.count > 1, let idx = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        let doomed = spaces[idx]
        if peekSession != nil { peekSession = nil }
        for tab in doomed.todayTabs where tab.kind == .web {
            archivedTabs.insert(
                ArchivedTab(title: tab.displayTitle, urlString: tab.urlString, spaceTitle: doomed.title, reason: "Space Deleted"),
                at: 0
            )
        }
        let ids = Set(doomed.allTabs.map { $0.id })
        for id in ids {
            WebViewPool.shared.destroyWebView(for: id)
            WebViewPool.shared.forgetTab(id)
        }
        recentTabIDs.removeAll { ids.contains($0) }
        let wasActive = (activeSpaceID == spaceID) || activeSpaceIndex == idx
        spaces.remove(at: idx)
        if wasActive {
            activeSpaceID = spaces[min(idx, spaces.count - 1)].id
            spaceTransitionDirection = -1
        }
        scheduleSave()
    }

    /// Removes one entry from the Archive list (the user's own action; the list is not capped).
    public func removeArchivedTab(id: UUID) {
        archivedTabs.removeAll { $0.id == id }
        scheduleSave()
    }

    public func clearArchive() {
        archivedTabs.removeAll()
        scheduleSave()
    }

    // MARK: - Split View Management

    /// Most panes a split can hold.
    public static let maxSplitPanes = 4

    /// Drops ids of tabs that no longer exist, and clears the split when fewer than two panes remain.
    private func pruneSplit(at sIdx: Int) {
        guard spaces.indices.contains(sIdx) else { return }
        let alive = spaces[sIdx].splitPaneTabIDs.filter { findTab(id: $0) != nil }
        spaces[sIdx].splitPaneTabIDs = alive.count > 1 ? alive : []
    }

    /// True when the active space is currently showing two or more panes.
    public var isSplitActive: Bool {
        visibleViewportTabIDs.count > 1
    }

    /// Adds a pane next to the active tab. With no `tabID` a new background tab is opened for it.
    public func addSplitPane(withTabID tabID: UUID? = nil) {
        guard let sIdx = activeSpaceIndex else { return }
        pruneSplit(at: sIdx)
        var currentSplit = spaces[sIdx].splitPaneTabIDs
        if currentSplit.isEmpty, let active = spaces[sIdx].activeTabID {
            currentSplit = [active]
        }
        if let explicitID = tabID, currentSplit.contains(explicitID) {
            // Already a pane: just focus it.
            spaces[sIdx].activeTabID = explicitID
            markTabActive(explicitID)
            scheduleSave()
            return
        }
        guard currentSplit.count < Self.maxSplitPanes else {
            showToast("Split View holds up to \(Self.maxSplitPanes) panes")
            return
        }
        let targetID: UUID
        if let explicitID = tabID {
            targetID = explicitID
        } else {
            let newTab = openNewTab(urlString: "https://www.google.com", inBackground: true)
            targetID = newTab.id
        }
        currentSplit.append(targetID)
        // openNewTab may have changed this space's tabs; look the index up again.
        guard let idx = activeSpaceIndex else { return }
        spaces[idx].splitPaneTabIDs = currentSplit
        spaces[idx].splitFractions = nil   // a new pane count starts from an even split
        spaces[idx].activeTabID = targetID
        markTabActive(targetID)
        scheduleSave()
    }

    /// Takes one pane out of the split (its tab stays open). With no `tabID`, the focused pane.
    /// Leaves split mode when fewer than two panes remain.
    public func removeSplitPane(tabID: UUID? = nil) {
        guard let sIdx = activeSpaceIndex else { return }
        let target = tabID ?? spaces[sIdx].activeTabID
        if let target, spaces[sIdx].splitPaneTabIDs.contains(target) {
            spaces[sIdx].splitPaneTabIDs.removeAll { $0 == target }
            spaces[sIdx].splitFractions = nil
            if spaces[sIdx].splitPaneTabIDs.count < 2 {
                // The remaining pane (if any) becomes the plain active tab.
                if let last = spaces[sIdx].splitPaneTabIDs.first { spaces[sIdx].activeTabID = last }
                spaces[sIdx].splitPaneTabIDs = []
            } else if spaces[sIdx].activeTabID == target {
                spaces[sIdx].activeTabID = spaces[sIdx].splitPaneTabIDs.first
            }
        } else {
            spaces[sIdx].splitPaneTabIDs = []
        }
        scheduleSave()
    }

    /// Leaves split mode entirely; every tab stays open.
    public func closeSplitView() {
        guard let sIdx = activeSpaceIndex else { return }
        spaces[sIdx].splitPaneTabIDs = []
        spaces[sIdx].splitFractions = nil
        scheduleSave()
    }

    /// Stores the pane sizes of a 3- or 4-pane split for the active space (normalised and clamped).
    public func setSplitFractions(_ fractions: [Double]) {
        guard let sIdx = activeSpaceIndex else { return }
        let count = spaces[sIdx].splitPaneTabIDs.count
        guard count > 2 else { return }
        spaces[sIdx].splitFractions = SplitPaneLayout.normalized(fractions, count: count)
        scheduleSave()
    }

    /// Puts `newTabID` into the pane showing `paneTabID`. The replaced tab stays open in the sidebar.
    /// If `newTabID` is already another pane the two panes trade places, so a tab is never in two panes.
    public func replaceSplitPane(_ paneTabID: UUID, with newTabID: UUID) {
        guard let sIdx = activeSpaceIndex else { return }
        pruneSplit(at: sIdx)
        var panes = spaces[sIdx].splitPaneTabIDs
        guard panes.count > 1,
              paneTabID != newTabID,
              let target = panes.firstIndex(of: paneTabID),
              let dragged = findTab(id: newTabID),
              dragged.isFavorite || spaces[sIdx].allTabs.contains(where: { $0.id == newTabID }) else { return }
        if let existing = panes.firstIndex(of: newTabID) {
            panes.swapAt(existing, target)
        } else {
            panes[target] = newTabID
        }
        spaces[sIdx].splitPaneTabIDs = panes
        spaces[sIdx].activeTabID = newTabID
        markTabActive(newTabID)
        scheduleSave()
    }

    /// A sidebar tab was dropped on the pane showing `paneTabID`. In a split it replaces that pane; on a single
    /// viewport it starts a split holding the current tab and the dropped tab (same checks as `replaceSplitPane`).
    public func dropSidebarTab(_ droppedID: UUID, onPane paneTabID: UUID) {
        guard let sIdx = activeSpaceIndex else { return }
        if isSplitActive {
            replaceSplitPane(paneTabID, with: droppedID)
            return
        }
        guard droppedID != paneTabID,
              let dragged = findTab(id: droppedID),
              dragged.isFavorite || spaces[sIdx].allTabs.contains(where: { $0.id == droppedID }) else { return }
        addSplitPane(withTabID: droppedID)
    }

    /// Grows (or shrinks) the focused pane by one keyboard step, taking the space from / giving it to its neighbour.
    /// Two panes use the single `splitRatio`; three or four use the per-space fractions. Same minimums as a drag.
    public func resizeFocusedSplitPane(grow: Bool) {
        guard let sIdx = activeSpaceIndex else { return }
        let panes = visibleViewportTabIDs
        guard panes.count > 1 else { return }
        let focused = spaces[sIdx].activeTabID.flatMap { panes.firstIndex(of: $0) } ?? 0
        let delta = (grow ? 1.0 : -1.0) * SplitPaneLayout.keyboardStep
        if panes.count == 2 {
            splitRatio = CGFloat(SplitPaneLayout.nudgedTwoPaneRatio(Double(splitRatio), pane: focused, delta: delta))
        } else {
            let current = SplitPaneLayout.normalized(spaces[sIdx].splitFractions, count: panes.count)
            spaces[sIdx].splitFractions = SplitPaneLayout.resizingPane(current, pane: focused, delta: delta)
        }
        scheduleSave()
    }

    /// Moves the focused pane one position forward (or backward) in the split order, swapping places with its neighbour.
    /// The pane keeps its size and focus. Does nothing at either end. Saved like a drag.
    public func moveFocusedSplitPane(forward: Bool) {
        guard let sIdx = activeSpaceIndex else { return }
        let panes = visibleViewportTabIDs
        guard panes.count > 1, panes == spaces[sIdx].splitPaneTabIDs,
              let focused = spaces[sIdx].activeTabID.flatMap({ panes.firstIndex(of: $0) }),
              let moved = SplitPaneLayout.swappingNeighbour(panes, index: focused, forward: forward) else { return }
        if panes.count == 2 {
            splitRatio = 1 - splitRatio   // the first pane's share now belongs to the other tab
        } else {
            let current = SplitPaneLayout.normalized(spaces[sIdx].splitFractions, count: panes.count)
            spaces[sIdx].splitFractions = SplitPaneLayout.swappingNeighbour(current, index: focused, forward: forward)
        }
        spaces[sIdx].splitPaneTabIDs = moved
        scheduleSave()
    }

    /// Moves focus to the next (or previous) pane, wrapping around.
    public func focusSplitPane(forward: Bool) {
        guard let sIdx = activeSpaceIndex else { return }
        let panes = visibleViewportTabIDs
        guard panes.count > 1 else { return }
        let current = spaces[sIdx].activeTabID.flatMap { panes.firstIndex(of: $0) } ?? 0
        let next = (current + (forward ? 1 : panes.count - 1)) % panes.count
        spaces[sIdx].activeTabID = panes[next]
        markTabActive(panes[next])
        scheduleSave()
    }

    public func toggleSplitOrientation() {
        guard let sIdx = activeSpaceIndex else { return }
        spaces[sIdx].splitOrientation = spaces[sIdx].splitOrientation == .horizontal ? .vertical : .horizontal
        scheduleSave()
    }

    // MARK: - Quick Peek Management

    public func openPeek(urlString: String, title: String, sourceTabID: UUID? = nil) {
        peekSession = PeekSession(urlString: urlString, title: title, sourceTabID: sourceTabID)
    }

    public func expandPeekToFullTab() {
        guard let session = peekSession else { return }
        // Use where the peek has navigated to, not just the link it opened with.
        let live = WebViewPool.shared.existingWebView(for: session.id)
        let urlString = live?.url?.absoluteString ?? session.urlString
        let title = live?.title.flatMap { $0.isEmpty ? nil : $0 } ?? session.title
        let newTab = openNewTab(urlString: urlString, title: title, inBackground: false)
        peekSession = nil
        selectTab(newTab.id)
    }

    /// Where the peek is now (it may have navigated away from the link it opened with).
    private func peekCurrentURLString(_ session: PeekSession) -> String {
        WebViewPool.shared.existingWebView(for: session.id)?.url?.absoluteString ?? session.urlString
    }

    /// Copies the page the peek is showing to the pasteboard.
    public func copyPeekLink() {
        guard let session = peekSession else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(peekCurrentURLString(session), forType: .string)
        showToast("Copied link")
    }

    /// Opens the page the peek is showing in a separate window (the compact Mini window) and closes the peek.
    public func openPeekInNewWindow() {
        guard let session = peekSession else { return }
        let urlString = peekCurrentURLString(session)
        peekSession = nil
        MiniAlpWindowController.shared.showWindow(initialURL: urlString)
    }

    // MARK: - Spaces Switching

    public func switchToSpace(at index: Int) {
        guard spaces.indices.contains(index) else { return }
        let currentIdx = activeSpaceIndex ?? 0
        if index != currentIdx, peekSession != nil { peekSession = nil }
        if index != currentIdx {
            spaceTransitionDirection = (index > currentIdx) ? 1 : -1
        }
        activeSpaceID = spaces[index].id
        scheduleSave()
    }

    public func switchToNextSpace(forward: Bool) {
        guard !spaces.isEmpty else { return }
        let currentIdx = activeSpaceIndex ?? 0
        if forward {
            if currentIdx < spaces.count - 1 {
                switchToSpace(at: currentIdx + 1)
            }
            // If already at rightmost space: do not wrap around; rebound handles visual cue
        } else {
            if currentIdx > 0 {
                switchToSpace(at: currentIdx - 1)
            } else {
                // If at leftmost space: swipe right reveals Library from the side
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isLibrarySheetPresented = true
                }
            }
        }
    }

    // MARK: - Canvas & Notes Management

    @discardableResult
    public func createNewCanvas(title: String = "Untitled Canvas") -> UUID {
        let canvas = AlpCanvas(title: title)
        canvases.insert(canvas, at: 0)
        openCanvas(id: canvas.id)
        scheduleSave()
        return canvas.id
    }

    @discardableResult
    public func createNewNote(title: String = "Untitled Note") -> UUID {
        let note = AlpNote(title: title)
        notes.insert(note, at: 0)
        openNote(id: note.id)
        scheduleSave()
        return note.id
    }

    /// Selects the tab already showing this easel, or opens one.
    public func openCanvas(id: UUID) {
        guard let canvas = canvases.first(where: { $0.id == id }) else { return }
        openOrSelectTab(kind: .canvas(id), urlString: "alp://canvas/\(id)", title: canvas.title)
    }

    /// Selects the tab already showing this note, or opens one.
    public func openNote(id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        openOrSelectTab(kind: .note(id), urlString: "alp://note/\(id)", title: note.title)
    }

    private func openOrSelectTab(kind: TabKind, urlString: String, title: String) {
        let allTabs = favorites + spaces.flatMap { $0.allTabs }
        if let existing = allTabs.first(where: { $0.kind == kind }) {
            selectTab(existing.id)
        } else {
            let tab = openNewTab(urlString: urlString, title: title, inBackground: false, kind: kind)
            selectTab(tab.id)
        }
    }

    public func renameCanvas(id: UUID, to title: String) {
        guard let idx = canvases.firstIndex(where: { $0.id == id }) else { return }
        canvases[idx].title = title
        canvases[idx].updatedAt = Date()
        retitleTabs(kind: .canvas(id), title: title)
        scheduleSave()
    }

    public func renameNote(id: UUID, to title: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].title = title
        notes[idx].updatedAt = Date()
        retitleTabs(kind: .note(id), title: title)
        scheduleSave()
    }

    private func retitleTabs(kind: TabKind, title: String) {
        let display = title.isEmpty ? "Untitled" : title
        let allTabs = favorites + spaces.flatMap { $0.allTabs }
        for tab in allTabs where tab.kind == kind {
            mutateTab(id: tab.id) { $0.title = display }
        }
    }

    public func deleteCanvas(id: UUID) {
        closeTabsShowing(kind: .canvas(id))
        canvases.removeAll { $0.id == id }
        scheduleSave()
    }

    public func deleteNote(id: UUID) {
        closeTabsShowing(kind: .note(id))
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    private func closeTabsShowing(kind: TabKind) {
        let allTabs = favorites + spaces.flatMap { $0.allTabs }
        for tab in allTabs where tab.kind == kind {
            closeTab(id: tab.id)
        }
    }

    // MARK: - Page Styles & Element Zapping

    public func addZappedSelector(_ selector: String, forTabID tabID: UUID) {
        guard let tab = findTab(id: tabID), let host = URL(string: tab.urlString)?.host else { return }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let idx = styles.firstIndex(where: { $0.domain == domain }) {
            if !styles[idx].zappedSelectors.contains(selector) {
                styles[idx].zappedSelectors.append(selector)
                styles[idx].updatedAt = Date()
            }
        } else {
            styles.append(PageMod(domain: domain, name: "\(domain) Boost", zappedSelectors: [selector]))
        }
        commitBoostChanges()
        showToast("Hidden element on \(domain)")
    }

    // MARK: - Boost management

    /// Persists boosts and pushes them to open tabs (user scripts for future loads, CSS for the current page).
    public func commitBoostChanges() {
        WebViewPool.shared.reapplyBoosts()
        scheduleSave()
    }

    public func setBoostEnabled(id: UUID, enabled: Bool) {
        guard let idx = styles.firstIndex(where: { $0.id == id }) else { return }
        styles[idx].isEnabled = enabled
        styles[idx].updatedAt = Date()
        commitBoostChanges()
    }

    public func deleteBoost(id: UUID) {
        styles.removeAll { $0.id == id }
        commitBoostChanges()
    }

    public func removeZappedSelector(_ selector: String, fromBoost id: UUID) {
        guard let idx = styles.firstIndex(where: { $0.id == id }) else { return }
        styles[idx].zappedSelectors.removeAll { $0 == selector }
        styles[idx].updatedAt = Date()
        commitBoostChanges()
    }

    // MARK: - Zero-RAM Tab Hibernation

    public func hibernateAllBackgroundTabsNow() async {
        let activeVisible = Set(visibleViewportTabIDs)
        let allTabs = favorites + spaces.flatMap { $0.allTabs }

        for tab in allTabs where !activeVisible.contains(tab.id) && !tab.isPlayingAudio {
            WebViewPool.shared.hibernateTab(id: tab.id)
            mutateTab(id: tab.id) { $0.isHibernated = true; $0.isLoading = false }
        }
        updateMemoryMetrics()
        showToast("Background tabs hibernated (0 MB RAM)")
    }

    /// When each live tab was last on screen. Drives the "hibernate after N minutes" setting.
    /// Keyed only by tabs that own a web view, so it cannot grow past the live set.
    private var lastVisibleAt: [UUID: Date] = [:]

    /// Hibernates live tabs that have been out of sight for `autoHibernateMinutes` (0 = never).
    /// Tabs shown in the viewport or split, and tabs playing audio, are never touched.
    public func performAutoHibernation(now: Date = Date()) {
        let live = Set(WebViewPool.shared.liveTabIDs)
        let visible = Set(visibleViewportTabIDs)
        lastVisibleAt = lastVisibleAt.filter { live.contains($0.key) }
        for id in live where visible.contains(id) || lastVisibleAt[id] == nil {
            lastVisibleAt[id] = now
        }
        guard autoHibernateMinutes > 0 else { return }

        let limit = autoHibernateMinutes * 60
        var hibernated = 0
        for id in live where !visible.contains(id) {
            guard let since = lastVisibleAt[id], now.timeIntervalSince(since) >= limit else { continue }
            if findTab(id: id)?.isPlayingAudio == true {
                lastVisibleAt[id] = now
                continue
            }
            WebViewPool.shared.hibernateTab(id: id)
            lastVisibleAt.removeValue(forKey: id)
            mutateTab(id: id) { $0.isHibernated = true; $0.isLoading = false }
            hibernated += 1
        }
        if hibernated > 0 { updateMemoryMetrics() }
    }

    // MARK: - Cloud Sync Management

    /// Uploads the vault. A second call while one is running is ignored. `overwriteRemote` replaces a cloud copy that was
    /// changed on another device (only the "Replace Cloud Copy" button passes it). The result is always shown in
    /// `syncStatusText` / `syncProblem`; a failure never touches local data.
    public func syncNow(silent: Bool = false, overwriteRemote: Bool = false) async {
        guard !isSyncInFlight else {
            if !silent { showToast("A sync is already running") }
            return
        }
        isSyncInFlight = true
        defer { isSyncInFlight = false }

        if !silent { syncStatusText = "Syncing..." }
        let store = buildPersistedStore()
        let result = await AlpSyncService.shared.pushStore(
            store,
            endpoint: syncConfig.syncEndpointURL,
            vaultID: syncConfig.syncVaultID,
            overwriteRemote: overwriteRemote
        )

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: Date())

        switch result {
        case .success:
            lastSyncedFingerprint = Self.syncFingerprint(of: store)
            syncConfig.lastSyncedAt = Date()
            isSyncConnected = true
            syncProblem = nil
            syncHasConflict = false
            syncStatusText = "Synced at \(timeStr) • AES-256-GCM"
            if !silent { showToast("Vault encrypted & synced") }
            scheduleSave()
        case .conflict(let message):
            isSyncConnected = true
            syncProblem = message
            syncHasConflict = true
            syncStatusText = "Needs attention"
            showToast("Sync paused: the cloud vault was changed on another device")   // shown even for background syncs
        case .offline(let message):
            isSyncConnected = false
            syncProblem = message
            syncHasConflict = false
            syncStatusText = "Saved on this Mac only"
            if !silent { showToast(message) }
        case .failure(let message):
            isSyncConnected = false
            syncProblem = message
            syncHasConflict = false
            syncStatusText = "Sync problem"
            if !silent { showToast(message) }
        }
    }

    /// Replaces this Mac's tabs and spaces with the cloud copy. A safety copy of the current state is written first and
    /// nothing is touched unless the cloud vault downloads, decrypts and holds at least one space.
    public func restoreVaultFromCloud() async {
        guard !isSyncInFlight else { showToast("A sync is already running"); return }
        isSyncInFlight = true
        defer { isSyncInFlight = false }

        syncStatusText = "Restoring vault..."
        do {
            switch try await AlpSyncService.shared.pullStore(
                endpoint: syncConfig.syncEndpointURL,
                vaultID: syncConfig.syncVaultID
            ) {
            case .restored(let store):
                applyRestoredStore(store)
                lastSyncedFingerprint = Self.syncFingerprint(of: buildPersistedStore())   // just downloaded: nothing to upload
                isSyncConnected = true
                syncProblem = nil
                syncHasConflict = false
                syncStatusText = "Vault restored successfully"
                showToast("Tabs and spaces restored from vault")
            case .noRemoteVault:
                syncProblem = nil
                syncStatusText = "No remote vault backup found"
                showToast("No cloud backup found for this vault name")
            }
        } catch {
            let message = (error as? AlpSyncError)?.errorDescription ?? error.localizedDescription
            syncProblem = message + " Nothing on this Mac was changed."
            syncStatusText = "Restore failed"
            showToast(message)
        }
    }

    /// Restores the encrypted copy kept on this Mac (what this device last backed up), after a safety copy of the current state.
    public func restoreVaultFromLocalBackup() async {
        guard !isSyncInFlight else { showToast("A sync is already running"); return }
        isSyncInFlight = true
        defer { isSyncInFlight = false }
        do {
            if let store = try await AlpSyncService.shared.loadLocalBackup(vaultID: syncConfig.syncVaultID) {
                applyRestoredStore(store)
                // Same as a cloud restore: the restored state is not a new local change. The conflict check still runs
                // before any later upload, so a cloud vault that changed since this backup is never overwritten.
                lastSyncedFingerprint = Self.syncFingerprint(of: buildPersistedStore())
                syncProblem = nil
                syncStatusText = "Restored from this Mac's backup"
                showToast("Restored from this Mac's encrypted backup")
            } else {
                showToast("There is no backup of this vault on this Mac yet")
            }
        } catch {
            let message = (error as? AlpSyncError)?.errorDescription ?? error.localizedDescription
            syncProblem = message
            showToast(message)
        }
    }

    /// Writes the current state to `store.pre-restore-<time>.json` next to the store (newest three kept), then applies
    /// `store` while keeping this Mac's own sync settings (endpoint, vault name, auto-sync), which a vault must not rewrite.
    private func applyRestoredStore(_ store: PersistedBrowserStore) {
        writePreRestoreSnapshot()
        let ownConfig = syncConfig
        let tabIDsBefore = allStoredTabIDs()
        applyPersistedStore(store)
        // Tabs that are gone after the restore must not keep a page running; tabs that survived are left alone.
        let gone = tabIDsBefore.subtracting(allStoredTabIDs())
        for id in gone {
            WebViewPool.shared.destroyWebView(for: id)
            WebViewPool.shared.forgetTab(id)
        }
        recentTabIDs.removeAll { gone.contains($0) }
        if let source = peekSession?.sourceTabID, gone.contains(source) { peekSession = nil }
        var config = ownConfig
        config.lastSyncedAt = Date()
        syncConfig = config
    }

    /// Ids of every tab in the store (all spaces and the favorites). Peek and Mini Alp tabs are not part of the store.
    private func allStoredTabIDs() -> Set<UUID> {
        var ids = Set(favorites.map { $0.id })
        for space in spaces { for tab in space.allTabs { ids.insert(tab.id) } }
        return ids
    }

    private func writePreRestoreSnapshot() {
        let dir = storeFileURL.deletingLastPathComponent()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("store.pre-restore-\(stamp).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(buildPersistedStore()).write(to: url, options: .atomic)
        } catch {
            print("Could not write pre-restore snapshot: \(error)")
        }
        let old = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("store.pre-restore-") }
            .sorted()
            .dropLast(3)
        for name in old { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    }

    public func performSilentSync() async {
        guard syncConfig.autoSyncEnabled else { return }
        await syncNow(silent: true)
    }

    /// Content fingerprint that ignores `lastSyncedAt`, so recording a finished sync does not look like a new change.
    /// It also ignores per-tab fields that change during ordinary browsing (last-active time, loading state, progress,
    /// audio and hibernation state), so only real edits mark the store as changed. The stored data is not altered.
    private static func syncFingerprint(of store: PersistedBrowserStore) -> String? {
        var copy = store
        copy.syncConfig.lastSyncedAt = nil
        copy.favorites = copy.favorites.map { normalisedForFingerprint($0) }
        for index in copy.spaces.indices {
            copy.spaces[index].pinnedNodes = copy.spaces[index].pinnedNodes.map { normalisedForFingerprint($0) }
            copy.spaces[index].todayTabs = copy.spaces[index].todayTabs.map { normalisedForFingerprint($0) }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(copy) else { return nil }
        return AlpSyncService.digest(of: data)
    }

    private static func normalisedForFingerprint(_ tab: TabItem) -> TabItem {
        var tab = tab
        tab.lastActiveAt = Date(timeIntervalSince1970: 0)
        tab.isLoading = false
        tab.estimatedProgress = 0
        tab.isPlayingAudio = false
        tab.isHibernated = false
        return tab
    }

    private static func normalisedForFingerprint(_ node: SidebarNode) -> SidebarNode {
        switch node {
        case .tab(let tab):
            return .tab(normalisedForFingerprint(tab))
        case .folder(var folder):
            folder.children = folder.children.map { normalisedForFingerprint($0) }
            return .folder(folder)
        }
    }

    /// Called on every store change. Restarts a quiet-period timer; the sync itself re-checks the toggle and the
    /// fingerprint when it fires, so a burst of edits costs one check, not one request each.
    private func noteStoreChangedForSync(after delay: TimeInterval = BrowserState.syncDebounceSeconds) {
        guard syncConfig.autoSyncEnabled else {
            syncDebounceTask?.cancel()
            syncDebounceTask = nil
            return
        }
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.autoSyncIfChanged()
        }
    }

    /// Background sync used by the debounce and the periodic timer. It runs the normal `syncNow` (GET first, fingerprint
    /// compare, never overwrite), but only when the toggle is on, no sync is running, the last conflict is resolved,
    /// the content differs from what was last synced, and the previous attempt was at least a minute ago.
    public func autoSyncIfChanged() async {
        guard syncConfig.autoSyncEnabled, !isSyncInFlight, !syncHasConflict, !spaces.isEmpty else { return }
        guard let current = Self.syncFingerprint(of: buildPersistedStore()), current != lastSyncedFingerprint else { return }
        if let last = lastAutoSyncAttempt {
            let wait = Self.minAutoSyncGapSeconds - Date().timeIntervalSince(last)
            if wait > 0 {
                noteStoreChangedForSync(after: wait + 1)
                return
            }
        }
        lastAutoSyncAttempt = Date()
        await syncNow(silent: true)
    }

    public func refreshSyncStatus() async {
        let (online, _) = await AlpSyncService.shared.checkServerHealth(endpoint: syncConfig.syncEndpointURL)
        isSyncConnected = online
        syncStatusText = online ? "Sync server reachable" : "Local Encrypted Vault Active"
    }

    // MARK: - App Icon Single-Click Selection

    public func selectAppIcon(named iconName: String) {
        selectedIconName = iconName
        UserDefaults.standard.set(iconName, forKey: "alp_selected_icon")

        if iconName == "custom" {
            if let customImg = AlpIconGenerator.generateCustomIcon(config: customIconConfig) {
                AlpIconGenerator.applyIcon(image: customImg)
            }
            showToast("Custom app icon applied")
        } else {
            if let iconImg = AlpIconGenerator.bundledIcon(named: iconName) {
                AlpIconGenerator.applyIcon(image: iconImg)
            }
            showToast("App icon updated")
        }
        scheduleSave()
    }

    public func updateCustomIconConfig(_ newConfig: CustomIconConfig) {
        customIconConfig = newConfig
        if selectedIconName == "custom" {
            if let img = AlpIconGenerator.generateCustomIcon(config: newConfig) {
                AlpIconGenerator.applyIcon(image: img)
            }
        }
        scheduleSave()
    }

    public func selectCustomIconImage(url: URL) {
        customIconConfig.customImagePath = url.path
        selectAppIcon(named: "custom")
    }

    public func resetCustomIconToMountain() {
        customIconConfig.customImagePath = nil
        selectAppIcon(named: "custom")
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
            selectedIconName: selectedIconName,
            customIconConfig: customIconConfig,
            sidebarWidth: Double(sidebarWidth),
            splitRatio: Double(splitRatio)
        )
    }

    /// Serial so writes land in order; the quit-time save runs `sync` on it and so can never be overtaken.
    private static let saveQueue = DispatchQueue(label: "app.alpbrowser.store-save", qos: .utility)

    public func scheduleSave() {
        noteStoreChangedForSync()
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveImmediately(inBackground: true)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    /// Snapshots the store on the main thread, then encodes and writes it. Debounced saves do the
    /// (pretty-printed, growing) JSON encode off the main thread; the quit-time save blocks until written.
    public func saveImmediately(inBackground: Bool = false) {
        let store = buildPersistedStore()
        let url = storeFileURL
        let write: @Sendable () -> Void = {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(store)
                try data.write(to: url, options: .atomic)
            } catch {
                print("Failed to save store: \(error)")
            }
        }
        if inBackground {
            Self.saveQueue.async(execute: write)
        } else {
            Self.saveQueue.sync(execute: write)
        }
    }

    public func applyPersistedStore(_ store: PersistedBrowserStore) {
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
        self.customIconConfig = store.customIconConfig
        // The old 256pt default was too thin; carry untouched stores up to the new default.
        self.sidebarWidth = store.sidebarWidth == 256.0 ? 296 : CGFloat(store.sidebarWidth)
        self.splitRatio = CGFloat(store.splitRatio)
        for idx in spaces.indices { pruneSplit(at: idx) }
        scheduleSave()
    }

    private func loadPersistedOrImportFromArc() {
        if let data = try? Data(contentsOf: storeFileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let store = try? decoder.decode(PersistedBrowserStore.self, from: data) {
                applyPersistedStore(store)
                if self.archivedTabs.isEmpty {
                    self.archivedTabs = AlpSidebarImporter.importArchivedTabs()
                }
                return
            }
            // A store file exists but cannot be read: keep a copy before a fresh start overwrites it.
            let backup = storeFileURL.deletingLastPathComponent()
                .appendingPathComponent("unreadable-store-\(Int(Date().timeIntervalSince1970)).json")
            try? data.write(to: backup, options: .atomic)
        }

        // Automatic 1-click import from local Arc.app if available
        performArcImport(isFirstRun: true)
    }

    /// Imports the user's own spaces, pinned tabs and favorites from a local Arc install (menu and Settings).
    /// Existing spaces, tabs and favorites are never replaced: only what is not already here is added.
    public func importFromInstalledArcBrowser() {
        performArcImport(isFirstRun: false)
    }

    private func performArcImport(isFirstRun: Bool) {
        _ = AlpExtensionManager.shared.importExtensionsFromArc(silent: true)
        do {
            let imported = try AlpSidebarImporter.importFromArc()
            let skippedNote = imported.skippedItems > 0 ? " (\(imported.skippedItems) skipped)" : ""
            if isFirstRun {
                // First launch always lands on a blank tab with the command bar open, imported tabs or not.
                var firstRunSpaces = imported.spaces
                let startTab = Self.makeStartTab()
                firstRunSpaces[0].todayTabs.insert(startTab, at: 0)
                firstRunSpaces[0].activeTabID = startTab.id
                self.spaces = firstRunSpaces
                self.favorites = imported.favorites
                self.archivedTabs = imported.archivedTabs
                self.activeSpaceID = firstRunSpaces.first?.id
                self.hasImportedFromArc = true
                isCommandBarPresented = true
                scheduleSave()
                showToast("Imported \(imported.totalImportedTabs) tabs and \(imported.archivedTabs.count) archived tabs from Arc\(skippedNote)")
                return
            }

            // Merge: skip spaces already imported, favorites and archived entries whose address is already here.
            let knownSpaceIDs = Set(spaces.compactMap { $0.originalArcID })
            var newSpaces = imported.spaces.filter { space in
                space.originalArcID.map { !knownSpaceIDs.contains($0) } ?? true
            }
            let knownFavoriteURLs = Set(favorites.map { $0.urlString })
            let newFavorites = imported.favorites.filter { !knownFavoriteURLs.contains($0.urlString) }
            let knownArchivedURLs = Set(archivedTabs.map { $0.urlString })
            let newArchived = imported.archivedTabs.filter { !knownArchivedURLs.contains($0.urlString) }
            guard !newSpaces.isEmpty || !newFavorites.isEmpty || !newArchived.isEmpty else {
                showToast("Everything from Arc is already here. Nothing was changed.")
                return
            }
            // An imported space may point at a favorite that was left out as a duplicate; start it on its own first tab.
            for idx in newSpaces.indices {
                newSpaces[idx].activeTabID = newSpaces[idx].todayTabs.first?.id ?? newSpaces[idx].allTabs.first?.id
            }
            let addedTabs = newSpaces.reduce(0) { $0 + $1.allTabs.count } + newFavorites.count
            spaces.append(contentsOf: newSpaces)
            favorites.append(contentsOf: newFavorites)
            archivedTabs.append(contentsOf: newArchived)
            if activeSpaceID == nil { activeSpaceID = spaces.first?.id }
            hasImportedFromArc = true
            scheduleSave()
            showToast("Added \(addedTabs) tabs and \(newArchived.count) archived tabs from Arc\(skippedNote)")
        } catch {
            // The import is all-or-nothing: nothing above has touched the current state.
            print("Sidebar import failed: \(error)")
            if isFirstRun {
                installDefaultSpaces()
                if case ArcImportError.notFound = error { return }
            }
            showToast(error.localizedDescription)
        }
    }

    /// The blank tab every first launch opens; the command bar is presented over it.
    private static func makeStartTab() -> TabItem {
        TabItem(title: "New Tab", urlString: "about:blank")
    }

    /// First-run fallback: Personal and Leisure spaces, with a blank tab and the command bar open.
    private func installDefaultSpaces() {
        let welcomeTab = Self.makeStartTab()
        let personalSpace = AlpSpace(
            title: "Personal",
            iconEmoji: "🧌",
            theme: .userPersonalSky,
            todayTabs: [welcomeTab],
            activeTabID: welcomeTab.id
        )
        let leisureSpace = AlpSpace(
            title: "Leisure",
            iconEmoji: "👹",
            theme: .userLeisurePlum
        )
        self.spaces = [personalSpace, leisureSpace]
        self.activeSpaceID = personalSpace.id
        isCommandBarPresented = true
        scheduleSave()
    }

    // MARK: - Background Maintenance & Memory Monitoring

    private func startMemoryAndMaintenanceTimers() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMemoryMetrics()
            }
        }
        memoryTimer?.tolerance = 10.0

        hibernateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performAutoHibernation()
            }
        }
        hibernateTimer?.tolerance = 10.0

        // Run auto-archive check 5s after startup, then every 15 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.performAutoArchiving()
        }

        Timer.scheduledTimer(withTimeInterval: 900.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performAutoArchiving()
            }
        }
    }

    public func performAutoArchiving() {
        guard autoArchiveHours > 0 else { return } // 0 = Never
        let expirationSeconds = autoArchiveHours * 3600.0
        let now = Date()
        var archivedCount = 0

        for sIdx in spaces.indices {
            let activeID = spaces[sIdx].activeTabID
            let splitIDs = Set(spaces[sIdx].splitPaneTabIDs)
            let expiredTabs = spaces[sIdx].todayTabs.filter { tab in
                guard tab.id != activeID && !tab.isPlayingAudio else { return false }
                guard !splitIDs.contains(tab.id) else { return false }
                let elapsed = now.timeIntervalSince(tab.lastActiveAt)
                return elapsed >= expirationSeconds
            }

            for tab in expiredTabs {
                WebViewPool.shared.destroyWebView(for: tab.id)
                WebViewPool.shared.forgetTab(tab.id)
                archivedTabs.insert(
                    ArchivedTab(
                        id: UUID(),
                        title: tab.displayTitle,
                        urlString: tab.urlString,
                        spaceTitle: spaces[sIdx].title,
                        archivedAt: now,
                        reason: "Auto-Archive (\(Int(autoArchiveHours))h)"
                    ),
                    at: 0
                )
                archivedCount += 1
            }

            spaces[sIdx].todayTabs.removeAll { tab in
                expiredTabs.contains(where: { $0.id == tab.id })
            }
            let expiredIDs = Set(expiredTabs.map(\.id))
            spaces[sIdx].splitPaneTabIDs.removeAll { expiredIDs.contains($0) }
            pruneSplit(at: sIdx)
        }

        if archivedCount > 0 {
            scheduleSave()
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
