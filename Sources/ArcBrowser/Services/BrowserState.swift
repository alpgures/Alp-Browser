import Foundation
import SwiftUI
import AppKit
import Combine
import Darwin

@MainActor
public final class BrowserState: ObservableObject {
    public static let shared = BrowserState()

    // MARK: - Core Sidebar & Spaces State
    @Published public var spaces: [ArcSpace] = []
    @Published public var favorites: [TabItem] = []
    @Published public var activeSpaceID: UUID?

    // MARK: - UI Chrome & Overlays State
    @Published public var isSidebarCollapsed: Bool = false
    @Published public var isSidebarHoverPeeking: Bool = false
    @Published public var sidebarWidth: CGFloat = 256

    @Published public var isCommandBarPresented: Bool = false
    @Published public var commandBarInitialQuery: String = ""

    @Published public var peekSession: PeekSession?
    @Published public var isFindAndAskBarPresented: Bool = false
    @Published public var isBoostStudioPresented: Bool = false
    @Published public var isThemePickerPresented: Bool = false
    @Published public var isLibrarySheetPresented: Bool = false
    @Published public var isSiteControlCenterPresented: Bool = false
    @Published public var selectedLibrarySection: LibrarySection = .archive

    // MARK: - Control+Tab Visual Switcher State
    @Published public var recentTabIDs: [UUID] = []
    @Published public var isTabSwitcherPresented: Bool = false
    @Published public var tabSwitcherSelectedIndex: Int = 0
    @Published public var draggedTabID: UUID?

    // MARK: - Arc Features State (Boosts, Easels, Notes, Archive)
    @Published public var boosts: [ArcBoost] = []
    @Published public var easels: [ArcEasel] = []
    @Published public var notes: [ArcNote] = []
    @Published public var archivedTabs: [ArchivedTab] = []

    // MARK: - Memory & Settings State
    @Published public var autoArchiveHours: Double = 12.0
    @Published public var autoHibernateMinutes: Double = 5.0
    @Published public var adBlockerEnabled: Bool = true
    @Published public var currentProcessMemoryMB: Double = 0.0
    @Published public var ociConfig: OCICloudConfig = OCICloudConfig()
    @Published public var ociStatusText: String = "Connected"
    @Published public var ociConnected: Bool = true
    @Published public var ociClaudeAvailable: Bool = true
    @Published public var toastMessage: String?

    public enum LibrarySection: String, CaseIterable, Identifiable {
        case archive = "Archive"
        case easels = "Easels"
        case notes = "Notes"
        case boosts = "Boosts"
        case ociCloud = "OCI Cloud"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .archive: return "archivebox"
            case .easels: return "scribble.variable"
            case .notes: return "note.text"
            case .boosts: return "bolt.fill"
            case .ociCloud: return "icloud.and.arrow.up"
            }
        }
    }

    private var hasImportedFromArc: Bool = false
    private var memoryTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?
    private var silentOCISyncWorkItem: DispatchWorkItem?

    private init() {
        WebViewPool.shared.browserState = self
        loadPersistedOrImportFromArc()
        startMemoryAndMaintenanceTimers()
        TrackpadGestureManager.shared.startMonitoring()
        Task {
            await refreshOCIConnectionStatus()
            await syncToOCICloudNow(silent: true)
        }
    }

    // MARK: - Active Space & Active Tab Computed Properties

    public var activeSpaceIndex: Int? {
        guard let id = activeSpaceID else { return spaces.indices.first }
        return spaces.firstIndex(where: { $0.id == id }) ?? spaces.indices.first
    }

    public var activeSpace: ArcSpace {
        get {
            if let idx = activeSpaceIndex {
                return spaces[idx]
            }
            return ArcSpace(title: "Personal", iconEmoji: "🧌", theme: .userPersonalSky)
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

    // MARK: - Back / Forward Navigation Helpers

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

    // MARK: - Control + Tab Visual Recent Tab Switcher

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

    public func StepTabSwitcher(backwards: Bool) {
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

    // MARK: - Tab Lookup & Selection

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

    // MARK: - Drag and Drop Tab Organization

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

    // MARK: - Screenshot / Capture to Easel (`⌘⇧2`)

    public func capturePageToEaselOrClipboard(sendToEasel: Bool = true) async {
        guard let tabID = activeTabID, let tab = findTab(id: tabID) else { return }
        if let img = await WebViewPool.shared.captureSnapshot(for: tabID) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        }
        if sendToEasel {
            if easels.isEmpty {
                createNewEasel(title: "\(activeSpace.title) Captures")
            } else {
                easels[0].elements.append(
                    EaselElement(
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
            showToast("Captured page to Clipboard & Easel")
        } else {
            showToast("Copied page snapshot to Clipboard")
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
    public func openNewTab(urlString: String, title: String? = nil, inBackground: Bool = false, kind: TabKind = .web) -> TabItem {
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

    /// Handles clicking the trailing button (`-` when focused on a pinned tab, `×` when unfocused or on a Today tab).
    public func handleTabTrailingButtonAction(for tab: TabItem) {
        let isFocused = (activeTabID == tab.id)
        if tab.isPinned || tab.isFavorite {
            if isFocused {
                closeTab(id: tab.id)
            } else {
                if let sIdx = activeSpaceIndex {
                    archivedTabs.insert(
                        ArchivedTab(
                            title: tab.displayTitle,
                            urlString: tab.urlString,
                            spaceTitle: spaces[sIdx].title,
                            reason: "Removed Pinned Tab"
                        ),
                        at: 0
                    )
                }
                deletePinnedTabPermanently(id: tab.id)
            }
        } else {
            closeTab(id: tab.id)
        }
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
                spaces[sIdx].activeTabID = spaces[sIdx].todayTabs.first?.id
            }
            spaces[sIdx].splitPaneTabIDs.removeAll { $0 == tabID }
            if spaces[sIdx].splitPaneTabIDs.count == 1 {
                spaces[sIdx].splitPaneTabIDs = []
            }
            scheduleSave()
            return
        }

        WebViewPool.shared.destroyWebView(for: tabID)

        for idx in spaces.indices {
            let oldIndex = spaces[idx].todayTabs.firstIndex(where: { $0.id == tabID })
            spaces[idx].todayTabs.removeAll { $0.id == tabID }
            spaces[idx].splitPaneTabIDs.removeAll { $0 == tabID }
            if spaces[idx].splitPaneTabIDs.count == 1 {
                spaces[idx].splitPaneTabIDs = []
            }
            if spaces[idx].activeTabID == tabID {
                if let oIdx = oldIndex, !spaces[idx].todayTabs.isEmpty {
                    let nextIdx = min(oIdx, spaces[idx].todayTabs.count - 1)
                    spaces[idx].activeTabID = spaces[idx].todayTabs[nextIdx].id
                } else {
                    spaces[idx].activeTabID = spaces[idx].todayTabs.first?.id
                }
            }
        }
        scheduleSave()
    }

    public func deletePinnedTabPermanently(id tabID: UUID) {
        WebViewPool.shared.destroyWebView(for: tabID)
        favorites.removeAll { $0.id == tabID }
        for idx in spaces.indices {
            spaces[idx].pinnedNodes = removeNode(id: tabID, from: spaces[idx].pinnedNodes)
            if spaces[idx].activeTabID == tabID {
                spaces[idx].activeTabID = spaces[idx].todayTabs.first?.id
            }
        }
        scheduleSave()
    }

    private func removeNode(id: UUID, from nodes: [SidebarNode]) -> [SidebarNode] {
        nodes.compactMap { node in
            switch node {
            case .tab(let tab):
                return tab.id == id ? nil : .tab(tab)
            case .folder(var folder):
                if folder.id == id { return nil }
                folder.children = removeNode(id: id, from: folder.children)
                return .folder(folder)
            }
        }
    }

    public func togglePinTab(id tabID: UUID) {
        guard let tab = findTab(id: tabID) else { return }
        if tab.isPinned {
            moveTabToToday(tabID: tabID)
        } else {
            moveTabToPinned(tabID: tabID)
        }
    }

    public func toggleFavorite(id tabID: UUID) {
        guard let tab = findTab(id: tabID) else { return }
        if tab.isFavorite {
            favorites.removeAll { $0.id == tabID }
            var demoted = tab
            demoted.isFavorite = false
            demoted.isPinned = true
            if let sIdx = activeSpaceIndex {
                spaces[sIdx].pinnedNodes.insert(.tab(demoted), at: 0)
            }
        } else {
            for idx in spaces.indices {
                spaces[idx].todayTabs.removeAll { $0.id == tabID }
                spaces[idx].pinnedNodes = removeNode(id: tabID, from: spaces[idx].pinnedNodes)
            }
            var fav = tab
            fav.isFavorite = true
            fav.isPinned = true
            fav.pinnedURLString = tab.urlString
            favorites.append(fav)
        }
        scheduleSave()
    }

    public func toggleFolderExpanded(folderID: UUID) {
        guard let sIdx = activeSpaceIndex else { return }
        spaces[sIdx].pinnedNodes = toggleFolderInNodes(folderID: folderID, nodes: spaces[sIdx].pinnedNodes)
        scheduleSave()
    }

    private func toggleFolderInNodes(folderID: UUID, nodes: [SidebarNode]) -> [SidebarNode] {
        nodes.map { node in
            switch node {
            case .tab(let t):
                return .tab(t)
            case .folder(var f):
                if f.id == folderID {
                    f.isExpanded.toggle()
                } else {
                    f.children = toggleFolderInNodes(folderID: folderID, nodes: f.children)
                }
                return .folder(f)
            }
        }
    }

    public func createNewFolder(named title: String = "New Folder") {
        guard let sIdx = activeSpaceIndex else { return }
        let folder = FolderItem(title: title, isExpanded: true, children: [])
        spaces[sIdx].pinnedNodes.insert(.folder(folder), at: 0)
        scheduleSave()
    }

    public func clearTodayTabs() {
        guard let sIdx = activeSpaceIndex else { return }
        let clearing = spaces[sIdx].todayTabs
        guard !clearing.isEmpty else { return }

        for tab in clearing {
            WebViewPool.shared.destroyWebView(for: tab.id)
            archivedTabs.insert(
                ArchivedTab(
                    title: tab.displayTitle,
                    urlString: tab.urlString,
                    spaceTitle: spaces[sIdx].title,
                    reason: "Cleared Today Tabs"
                ),
                at: 0
            )
        }
        spaces[sIdx].todayTabs.removeAll()
        spaces[sIdx].activeTabID = spaces[sIdx].allPinnedTabs.first?.id ?? favorites.first?.id
        scheduleSave()
    }

    // MARK: - Split View Management

    public func addSplitPane(withTabID secondTabID: UUID? = nil, insertAtLeading: Bool = false) {
        guard let sIdx = activeSpaceIndex else { return }
        let primaryID = spaces[sIdx].activeTabID
            ?? spaces[sIdx].todayTabs.first?.id
            ?? spaces[sIdx].allPinnedTabs.first?.id

        guard let firstID = primaryID else { return }

        var panes = spaces[sIdx].splitPaneTabIDs.filter { findTab(id: $0) != nil }
        if panes.isEmpty {
            panes = [firstID]
        }
        guard panes.count < 4 else { return }

        let targetSecondID: UUID
        if let provided = secondTabID, !panes.contains(provided) {
            targetSecondID = provided
        } else {
            let newTab = openNewTab(urlString: "https://www.google.com", title: "Google", inBackground: true)
            targetSecondID = newTab.id
        }

        if insertAtLeading {
            panes.insert(targetSecondID, at: 0)
        } else {
            panes.append(targetSecondID)
        }
        spaces[sIdx].splitPaneTabIDs = panes
        spaces[sIdx].activeTabID = targetSecondID
        markTabActive(targetSecondID)
        scheduleSave()
    }

    public func removeSplitPane(tabID: UUID? = nil) {
        guard let sIdx = activeSpaceIndex else { return }
        let target = tabID ?? spaces[sIdx].activeTabID
        if let t = target {
            spaces[sIdx].splitPaneTabIDs.removeAll { $0 == t }
        }
        if spaces[sIdx].splitPaneTabIDs.count <= 1 {
            spaces[sIdx].splitPaneTabIDs = []
        }
        if let remaining = spaces[sIdx].splitPaneTabIDs.first {
            spaces[sIdx].activeTabID = remaining
        }
        scheduleSave()
    }

    public func toggleSplitOrientation() {
        guard let sIdx = activeSpaceIndex else { return }
        spaces[sIdx].splitOrientation = (spaces[sIdx].splitOrientation == .horizontal) ? .vertical : .horizontal
        scheduleSave()
    }

    // MARK: - Spaces Management

    public func switchToSpace(at index: Int) {
        guard spaces.indices.contains(index) else { return }
        if let currentIdx = activeSpaceIndex {
            TrackpadGestureManager.shared.spaceTransitionDirection = (index >= currentIdx) ? 1 : -1
        }
        withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 340, damping: 31)) {
            activeSpaceID = spaces[index].id
        }
        scheduleSave()
    }

    public func switchToNextSpace(forward: Bool = true) {
        guard !spaces.isEmpty, let currentIdx = activeSpaceIndex else { return }
        let nextIdx = forward
            ? (currentIdx + 1) % spaces.count
            : (currentIdx - 1 + spaces.count) % spaces.count
        TrackpadGestureManager.shared.spaceTransitionDirection = forward ? 1 : -1
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            activeSpaceID = spaces[nextIdx].id
        }
        scheduleSave()
    }

    public func createNewSpace(title: String = "New Space", emoji: String = "🚀") {
        let presetTheme = SpaceTheme.presets[spaces.count % SpaceTheme.presets.count].theme
        let welcomeTab = TabItem(title: "Start Page", urlString: "https://www.google.com")
        let space = ArcSpace(
            title: title,
            iconEmoji: emoji,
            theme: presetTheme,
            pinnedNodes: [],
            todayTabs: [welcomeTab],
            activeTabID: welcomeTab.id
        )
        spaces.append(space)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            activeSpaceID = space.id
        }
        scheduleSave()
    }

    // MARK: - Peek & Little Arc

    public func openPeek(urlString: String, title: String, sourceTabID: UUID?) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
            peekSession = PeekSession(urlString: urlString, title: title, sourceTabID: sourceTabID)
        }
    }

    public func expandPeekToFullTab() {
        guard let peek = peekSession else { return }
        let tab = openNewTab(urlString: peek.urlString, title: peek.title, inBackground: false)
        selectTab(tab.id)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            peekSession = nil
        }
    }

    // MARK: - Easels & Notes Creation

    public func createNewEasel(title: String = "Untitled Easel") {
        let easel = ArcEasel(
            title: title,
            elements: [
                EaselElement(
                    kind: .textHeader,
                    text: title,
                    x: 80,
                    y: 60,
                    width: 340,
                    height: 64,
                    color: activeTheme.primaryColor
                ),
                EaselElement(
                    kind: .stickyNote,
                    text: "Double-click any card to edit text, drag to arrange, or capture live web links.",
                    x: 80,
                    y: 150,
                    width: 260,
                    height: 160,
                    color: RGBAColor(red: 0.99, green: 0.91, blue: 0.52)
                )
            ]
        )
        easels.insert(easel, at: 0)
        openNewTab(urlString: "arc://easel/\(easel.id.uuidString)", title: "🎨 \(title)", inBackground: false, kind: .easel(easel.id))
        scheduleSave()
    }

    public func createNewNote(title: String = "Quick Note") {
        let note = ArcNote(
            title: title,
            body: "# \(title)\n\nWrite thoughts, snippets, or research notes right next to your tabs..."
        )
        notes.insert(note, at: 0)
        openNewTab(urlString: "arc://note/\(note.id.uuidString)", title: "📝 \(title)", inBackground: false, kind: .note(note.id))
        scheduleSave()
    }

    // MARK: - Boosts 2.0 Management

    public func boost(forDomain domain: String) -> ArcBoost? {
        let clean = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        return boosts.first(where: { $0.domain.caseInsensitiveCompare(clean) == .orderedSame })
    }

    public func upsertBoost(_ boost: ArcBoost) {
        if let idx = boosts.firstIndex(where: { $0.id == boost.id || $0.domain.caseInsensitiveCompare(boost.domain) == .orderedSame }) {
            boosts[idx] = boost
        } else {
            boosts.insert(boost, at: 0)
        }
        if let activeID = activeTabID {
            WebViewPool.shared.applyBoost(boost, to: activeID)
        }
        scheduleSave()
    }

    public func addZappedSelector(_ selector: String, forTabID tabID: UUID) {
        guard let tab = findTab(id: tabID) else { return }
        let domain = tab.simplifiedDomain
        var current = boost(forDomain: domain) ?? ArcBoost(domain: domain, name: "\(domain) Boost")
        if !current.zappedSelectors.contains(selector) {
            current.zappedSelectors.append(selector)
        }
        upsertBoost(current)
    }

    // MARK: - Arc Max Tidy Tabs

    public func tidyTodayTabs() {
        guard let sIdx = activeSpaceIndex else { return }
        for idx in spaces[sIdx].todayTabs.indices {
            let host = spaces[sIdx].todayTabs[idx].simplifiedDomain.lowercased()
            let category: String
            if host.contains("github") || host.contains("stackoverflow") || host.contains("localhost") || host.contains("docs") {
                category = "Development"
            } else if host.contains("youtube") || host.contains("reddit") || host.contains("x.com") || host.contains("twitter") || host.contains("netflix") {
                category = "Media & Social"
            } else if host.contains("amazon") || host.contains("ebay") || host.contains("shop") {
                category = "Shopping"
            } else {
                category = "Research & Web"
            }
            spaces[sIdx].todayTabs[idx].todayCategory = category
        }
        spaces[sIdx].todayTabs.sort { ($0.todayCategory ?? "") < ($1.todayCategory ?? "") }
        scheduleSave()
    }

    // MARK: - Navigation Delegate Callback

    public func updateTabNavigationState(
        tabID: UUID,
        title: String?,
        urlString: String?,
        isLoading: Bool,
        progress: Double
    ) {
        mutateTab(id: tabID) { tab in
            if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tab.title = t
            }
            if let u = urlString, !u.isEmpty {
                tab.urlString = u
            }
            tab.isLoading = isLoading
            tab.estimatedProgress = progress
        }
    }

    public func mutateTab(id: UUID, transform: (inout TabItem) -> Void) {
        if let fIdx = favorites.firstIndex(where: { $0.id == id }) {
            transform(&favorites[fIdx])
            return
        }
        for sIdx in spaces.indices {
            if let tIdx = spaces[sIdx].todayTabs.firstIndex(where: { $0.id == id }) {
                transform(&spaces[sIdx].todayTabs[tIdx])
                return
            }
            if mutateTabInNodes(id: id, nodes: &spaces[sIdx].pinnedNodes, transform: transform) {
                return
            }
        }
    }

    private func mutateTabInNodes(id: UUID, nodes: inout [SidebarNode], transform: (inout TabItem) -> Void) -> Bool {
        for idx in nodes.indices {
            switch nodes[idx] {
            case .tab(var t):
                if t.id == id {
                    transform(&t)
                    nodes[idx] = .tab(t)
                    return true
                }
            case .folder(var f):
                if mutateTabInNodes(id: id, nodes: &f.children, transform: transform) {
                    nodes[idx] = .folder(f)
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Memory Optimization & Hibernation

    public func hibernateAllBackgroundTabsNow() async {
        let keepAlive = Set(visibleViewportTabIDs)
        let allTabs = favorites + spaces.flatMap { $0.allTabs }

        for tab in allTabs where !keepAlive.contains(tab.id) {
            if WebViewPool.shared.hasLiveWebView(for: tab.id) {
                await WebViewPool.shared.hibernateTab(id: tab.id)
                mutateTab(id: tab.id) { $0.isHibernated = true }
            }
        }
        updateProcessMemoryFootprint()
    }

    private func startMemoryAndMaintenanceTimers() {
        updateProcessMemoryFootprint()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.updateProcessMemoryFootprint()
                await self.checkIdleTabsForAutoHibernation()
                self.checkAutoArchiveTodayTabs()
            }
        }
    }

    public func updateProcessMemoryFootprint() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            currentProcessMemoryMB = Double(info.phys_footprint) / (1024.0 * 1024.0)
        }
    }

    private func checkIdleTabsForAutoHibernation() async {
        let thresholdSeconds = max(autoHibernateMinutes * 60.0, 60.0)
        let now = Date()
        let keepAlive = Set(visibleViewportTabIDs)
        let allTabs = favorites + spaces.flatMap { $0.allTabs }

        for tab in allTabs where !keepAlive.contains(tab.id) && !tab.isPlayingAudio {
            if WebViewPool.shared.hasLiveWebView(for: tab.id),
               now.timeIntervalSince(tab.lastActiveAt) > thresholdSeconds {
                await WebViewPool.shared.hibernateTab(id: tab.id)
                mutateTab(id: tab.id) { $0.isHibernated = true }
            }
        }
    }

    private func checkAutoArchiveTodayTabs() {
        let thresholdSeconds = max(autoArchiveHours * 3600.0, 600.0)
        let now = Date()
        let keepAlive = Set(visibleViewportTabIDs)

        for sIdx in spaces.indices {
            var remaining: [TabItem] = []
            for tab in spaces[sIdx].todayTabs {
                if !keepAlive.contains(tab.id) && now.timeIntervalSince(tab.lastActiveAt) > thresholdSeconds {
                    WebViewPool.shared.destroyWebView(for: tab.id)
                    archivedTabs.insert(
                        ArchivedTab(
                            title: tab.displayTitle,
                            urlString: tab.urlString,
                            spaceTitle: spaces[sIdx].title,
                            reason: "Auto-Archive (\(Int(autoArchiveHours))h)"
                        ),
                        at: 0
                    )
                } else {
                    remaining.append(tab)
                }
            }
            spaces[sIdx].todayTabs = remaining
        }
    }

    // MARK: - Import from Installed Arc & Silent OCI Persistence

    public func importFromInstalledArcBrowser() {
        do {
            let imported = try ArcSidebarImporter.importFromArc()
            guard !imported.spaces.isEmpty else { return }
            self.spaces = imported.spaces
            self.favorites = imported.favorites
            self.activeSpaceID = imported.spaces.first?.id
            self.hasImportedFromArc = true
            saveImmediately()
            scheduleSilentOCISync()
        } catch {
            // Silent error handling
        }
    }

    public func refreshOCIConnectionStatus() async {
        let status = await OCISyncService.shared.checkOCIConnection(sshAlias: ociConfig.sshHostAlias)
        ociConnected = status.connected
        ociClaudeAvailable = status.claudeAvailable
        if status.connected {
            ociStatusText = "Auto-Sync Active (\(status.hostname))"
        } else {
            ociStatusText = "Offline (\(ociConfig.sshHostAlias))"
        }
    }

    public func syncToOCICloudNow(silent: Bool = true) async {
        guard ociConfig.autoSyncEnabled || !silent else { return }
        let store = currentPersistedStore()
        let result = await OCISyncService.shared.pushStore(store, sshAlias: ociConfig.sshHostAlias)
        if case .success = result {
            ociConfig.lastSyncedAt = Date()
            ociConnected = true
        }
    }

    public func restoreFromOCICloudNow() async {
        if let remoteStore = try? await OCISyncService.shared.pullStore(sshAlias: ociConfig.sshHostAlias) {
            applyPersistedStore(remoteStore)
            saveImmediately()
        }
    }

    public func showToast(_ text: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.toastMessage == text {
                withAnimation(.easeOut(duration: 0.2)) {
                    self?.toastMessage = nil
                }
            }
        }
    }

    // MARK: - Persistence Implementation

    private var persistenceFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Arc2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("arc2_state.json")
    }

    private func currentPersistedStore() -> PersistedBrowserStore {
        PersistedBrowserStore(
            spaces: spaces,
            favorites: favorites,
            activeSpaceID: activeSpaceID,
            boosts: boosts,
            easels: easels,
            notes: notes,
            archivedTabs: Array(archivedTabs.prefix(300)),
            autoArchiveHours: autoArchiveHours,
            autoHibernateMinutes: autoHibernateMinutes,
            adBlockerEnabled: adBlockerEnabled,
            ociConfig: ociConfig,
            hasImportedFromArc: hasImportedFromArc
        )
    }

    private func applyPersistedStore(_ store: PersistedBrowserStore) {
        self.spaces = store.spaces
        self.favorites = store.favorites
        self.activeSpaceID = store.activeSpaceID ?? store.spaces.first?.id
        self.boosts = store.boosts
        self.easels = store.easels
        self.notes = store.notes
        self.archivedTabs = store.archivedTabs
        self.autoArchiveHours = store.autoArchiveHours
        self.autoHibernateMinutes = store.autoHibernateMinutes
        self.adBlockerEnabled = store.adBlockerEnabled
        self.ociConfig = store.ociConfig
        self.hasImportedFromArc = store.hasImportedFromArc
    }

    private func loadPersistedOrImportFromArc() {
        if FileManager.default.fileExists(atPath: persistenceFileURL.path),
           let data = try? Data(contentsOf: persistenceFileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(PersistedBrowserStore.self, from: data), !decoded.spaces.isEmpty {
                applyPersistedStore(decoded)
                syncExactThemesFromArcIfNeeded()
                return
            }
        }

        if ArcSidebarImporter.isArcInstalledDataAvailable,
           let imported = try? ArcSidebarImporter.importFromArc(),
           !imported.spaces.isEmpty {
            self.spaces = imported.spaces
            self.favorites = imported.favorites
            self.activeSpaceID = imported.spaces.first?.id
            self.hasImportedFromArc = true
            saveImmediately()
            return
        }

        let personalSpace = ArcSpace(
            title: "Personal",
            iconEmoji: "🧌",
            theme: .userPersonalSky,
            pinnedNodes: [],
            todayTabs: []
        )
        let leisureSpace = ArcSpace(
            title: "Leisure",
            iconEmoji: "👹",
            theme: .userLeisurePlum,
            pinnedNodes: [],
            todayTabs: []
        )
        self.spaces = [personalSpace, leisureSpace]
        self.activeSpaceID = personalSpace.id
        saveImmediately()
    }

    private func syncExactThemesFromArcIfNeeded() {
        guard ArcSidebarImporter.isArcInstalledDataAvailable,
              let imported = try? ArcSidebarImporter.importFromArc() else { return }

        for idx in spaces.indices {
            if let match = imported.spaces.first(where: {
                ($0.arcOriginalID != nil && $0.arcOriginalID == spaces[idx].arcOriginalID) ||
                $0.title == spaces[idx].title
            }) {
                spaces[idx].theme = match.theme
            }
        }
        saveImmediately()
    }

    public func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.saveImmediately()
                self.scheduleSilentOCISync()
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func scheduleSilentOCISync() {
        guard ociConfig.autoSyncEnabled else { return }
        silentOCISyncWorkItem?.cancel()
        let syncItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await self?.syncToOCICloudNow(silent: true)
            }
        }
        silentOCISyncWorkItem = syncItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: syncItem)
    }

    public func saveImmediately() {
        let store = currentPersistedStore()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(store) {
            try? data.write(to: persistenceFileURL, options: .atomic)
        }
    }
}
