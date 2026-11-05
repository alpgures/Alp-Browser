//
//  SidebarLibraryView.swift
//  Alp Browser
//
//  In-sidebar dual-column Library view.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers

public enum LibraryRailSection: String, CaseIterable, Identifiable {
    case media = "Media"
    case downloads = "Downloads"
    case easels = "Easels"
    case notes = "Notes"
    case spaces = "Spaces"
    case boosts = "Boosts"
    case archive = "Archived Tabs"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .downloads: return "arrow.down.circle"
        case .easels: return "pencil.tip.crop.circle"
        case .notes: return "note.text"
        case .spaces: return "square.3.layers.3d"
        case .boosts: return "sparkles"
        case .archive: return "archivebox"
        }
    }
}

public struct SidebarLibraryView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var selectedSection: LibraryRailSection = .archive
    @State private var searchQuery: String = ""
    @State private var downloadFiles: [URL] = []
    @State private var mediaFiles: [URL] = []
    @ObservedObject private var tracker = DownloadTracker.shared
    @State private var archiveFilter: ArchiveFilter = .all
    @State private var confirmClearArchive = false
    @State private var editingBoostID: UUID?

    enum ArchiveFilter: String, CaseIterable, Identifiable {
        case all = "All Time"
        case day = "Last 24 Hours"
        case week = "Last 7 Days"
        case older = "Older"
        var id: String { rawValue }
    }

    private var theme: SpaceTheme {
        browserState.activeTheme
    }

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Left rail column (no divider, items vertically centred)
            railColumn
                .frame(width: 74)

            // Right Content Sub-panel
            contentColumn
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.foregroundColor)
        .onAppear {
            Self.setWindowTrafficLights(hidden: true)
            if let requested = browserState.requestedLibrarySection {
                selectedSection = requested
                browserState.requestedLibrarySection = nil
            }
            reloadDownloads()
        }
        .onChange(of: selectedSection) { _, _ in
            searchQuery = ""
            if selectedSection == .downloads || selectedSection == .media { reloadDownloads() }
        }
        .onChange(of: tracker.finishedCount) { _, _ in reloadDownloads() }
        .onDisappear { Self.setWindowTrafficLights(hidden: false) }
        .confirmationDialog("Clear the whole Archive?", isPresented: $confirmClearArchive) {
            Button("Clear Archive", role: .destructive) { browserState.clearArchive() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every archived tab from the list. Open tabs are not affected.")
        }
    }

    /// The window's traffic lights are hidden while the Library occupies the sidebar.
    static func setWindowTrafficLights(hidden: Bool) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.fullSizeContentView) }) else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            for type in buttons {
                window.standardWindowButton(type)?.animator().alphaValue = hidden ? 0 : 1
            }
        }
        for type in buttons {
            window.standardWindowButton(type)?.isEnabled = !hidden
        }
    }

    // MARK: - Left Rail Column

    private var railColumn: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                ForEach(LibraryRailSection.allCases) { section in
                    railButton(for: section)
                }
            }

            Spacer(minLength: 12)

            // Bottom: back to sidebar + invite (back arrow and gift)
            HStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                        browserState.isLibrarySheetPresented = false
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AlpIconButtonStyle(theme: theme))
                .help("Back to Sidebar")

                Spacer(minLength: 0)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("https://alpbrowser.app", forType: .string)
                    browserState.showToast("Invite link copied")
                } label: {
                    Image(systemName: "gift")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AlpIconButtonStyle(theme: theme))
                .help("Invite a Friend")
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func railButton(for section: LibraryRailSection) -> some View {
        let isSelected = (selectedSection == section)

        Button {
            if section == .spaces {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                    browserState.isLibrarySheetPresented = false
                }
            } else {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
                    selectedSection = section
                }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: section.iconName)
                    .font(.system(size: 17, weight: .regular))
                    .frame(height: 20)

                Text(section.rawValue)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? theme.foregroundColor : theme.foregroundColor.opacity(0.72))
            .frame(width: 66, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? theme.selectionBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.rawValue)
    }

    // MARK: - Right Content Sub-Panel

    @ViewBuilder
    private var contentColumn: some View {
        VStack(spacing: 8) {
            // Top Search & Filter Bar
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryForegroundColor)
                    TextField(searchPlaceholder, text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.foregroundColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(theme.pillBackground)
                )

                if selectedSection == .archive {
                    Menu {
                        ForEach(ArchiveFilter.allCases) { option in
                            Button {
                                archiveFilter = option
                            } label: {
                                if archiveFilter == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 10.5))
                            Text("Filter")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(archiveFilter == .all ? theme.secondaryForegroundColor : theme.effectiveAccentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(theme.pillBackground)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(.top, 10)
            .padding(.leading, 4)
            .padding(.trailing, 8)

            // Content List depending on selectedSection
            ScrollView(.vertical, showsIndicators: false) {
                switch selectedSection {
                case .archive:
                    archiveListView
                case .easels:
                    easelsListView
                case .notes:
                    notesListView
                case .downloads:
                    downloadsListView
                case .boosts:
                    boostsListView
                case .media:
                    mediaListView
                case .spaces:
                    EmptyView()
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var searchPlaceholder: String {
        switch selectedSection {
        case .archive: return "Search Archive..."
        case .easels: return "Search Easels..."
        case .notes: return "Search Notes..."
        case .downloads: return "Search Downloads..."
        case .boosts: return "Search Boosts..."
        case .media: return "Search Media..."
        case .spaces: return "Search..."
        }
    }

    // MARK: - Archive List View (Grouped by Today, Yesterday, Previous 7 Days)

    private var filteredArchivedTabs: [ArchivedTab] {
        let now = Date()
        var tabs = browserState.archivedTabs.filter { tab in
            switch archiveFilter {
            case .all: return true
            case .day: return now.timeIntervalSince(tab.archivedAt) <= 86_400
            case .week: return now.timeIntervalSince(tab.archivedAt) <= 7 * 86_400
            case .older: return now.timeIntervalSince(tab.archivedAt) > 7 * 86_400
            }
        }
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            tabs = tabs.filter {
                $0.title.lowercased().contains(q) || $0.urlString.lowercased().contains(q)
            }
        }
        return tabs
    }

    private var archiveListView: some View {
        let tabs = filteredArchivedTabs
        let calendar = Calendar.current
        let todayTabs = tabs.filter { calendar.isDateInToday($0.archivedAt) }
        let yesterdayTabs = tabs.filter { calendar.isDateInYesterday($0.archivedAt) }
        let olderTabs = tabs.filter { !calendar.isDateInToday($0.archivedAt) && !calendar.isDateInYesterday($0.archivedAt) }

        return VStack(alignment: .leading, spacing: 10) {
            if tabs.isEmpty {
                VStack(spacing: 6) {
                    Text("No archived tabs")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryForegroundColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                if !todayTabs.isEmpty {
                    archiveSection(title: "Today", items: todayTabs)
                }
                if !yesterdayTabs.isEmpty {
                    archiveSection(title: "Yesterday", items: yesterdayTabs)
                }
                if !olderTabs.isEmpty {
                    archiveSection(title: "Previous Days", items: olderTabs)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func archiveSection(title: String, items: [ArchivedTab]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryForegroundColor.opacity(0.8))
                .padding(.leading, 6)
                .padding(.top, 6)

            ForEach(items) { tab in
                ArchivedTabRowItem(tab: tab, theme: theme) {
                    browserState.openNewTab(urlString: tab.urlString, title: tab.title)
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                        browserState.isLibrarySheetPresented = false
                    }
                }
                .contextMenu {
                    Button("Open in New Tab") {
                        browserState.openNewTab(urlString: tab.urlString, title: tab.title)
                        closeLibrary()
                    }
                    Button("Copy URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tab.urlString, forType: .string)
                    }
                    Divider()
                    Button("Remove from Archive", role: .destructive) {
                        browserState.removeArchivedTab(id: tab.id)
                    }
                    Button("Clear Archive…", role: .destructive) {
                        confirmClearArchive = true
                    }
                }
            }
        }
    }

    // MARK: - Easels List View

    private func libraryHeader(title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(action: action) {
                Label(title, systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.effectiveAccentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
    }

    private func libraryRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.effectiveAccentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.isEmpty ? "Untitled" : title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.foregroundColor)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.secondaryForegroundColor)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.hoverBackground.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func closeLibrary() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            browserState.isLibrarySheetPresented = false
        }
    }

    private var visibleCanvases: [AlpCanvas] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = browserState.canvases.sorted { $0.updatedAt > $1.updatedAt }
        return q.isEmpty ? sorted : sorted.filter { $0.title.lowercased().contains(q) }
    }

    private var easelsListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            libraryHeader(title: "New Easel") {
                browserState.createNewCanvas()
                closeLibrary()
            }
            let items = visibleCanvases
            if items.isEmpty {
                Text(browserState.canvases.isEmpty ? "No easels yet" : "No matching easels")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .padding()
            } else {
                ForEach(items) { canvas in
                    libraryRow(
                        icon: "pencil.and.outline",
                        title: canvas.title,
                        subtitle: "\(canvas.elements.count) items"
                    ) {
                        browserState.openCanvas(id: canvas.id)
                        closeLibrary()
                    }
                    .contextMenu {
                        Button("Delete Easel", role: .destructive) {
                            browserState.deleteCanvas(id: canvas.id)
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    private var visibleNotes: [AlpNote] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = browserState.notes.sorted { $0.updatedAt > $1.updatedAt }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) }
    }

    private var notesListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            libraryHeader(title: "New Note") {
                browserState.createNewNote()
                closeLibrary()
            }
            let items = visibleNotes
            if items.isEmpty {
                Text(browserState.notes.isEmpty ? "No notes yet" : "No matching notes")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .padding()
            } else {
                ForEach(items) { note in
                    libraryRow(
                        icon: "note.text",
                        title: note.title,
                        subtitle: String(note.body.prefix(60)).replacingOccurrences(of: "\n", with: " ")
                    ) {
                        browserState.openNote(id: note.id)
                        closeLibrary()
                    }
                    .contextMenu {
                        Button("Delete Note", role: .destructive) {
                            browserState.deleteNote(id: note.id)
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    // MARK: - Downloads List View

    private func reloadDownloads() {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            downloadFiles = []
            return
        }
        // Directory scan runs off the main actor; only the @State writes hop back.
        Task.detached(priority: .userInitiated) {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
            let files = (try? FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let dated: [(URL, Date)] = files.compactMap { url in
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
                return (url, v.contentModificationDate ?? .distantPast)
            }
            let sorted = dated.sorted { $0.1 > $1.1 }.prefix(200).map { $0.0 }
            let media = sorted.filter { Self.isMedia($0) }
            await MainActor.run {
                downloadFiles = sorted
                mediaFiles = media
            }
        }
    }

    nonisolated private static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .audio)
    }

    private var recentDownloads: [URL] {
        let inFlight = Set(tracker.active.map { $0.fileURL.path })
        let files = downloadFiles.filter { !inFlight.contains($0.path) }
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(files.prefix(25))
        }
        let q = searchQuery.lowercased()
        return files.filter { $0.lastPathComponent.lowercased().contains(q) }
    }

    private var downloadsListView: some View {
        let files = recentDownloads
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Downloads")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.foregroundColor)
                Spacer()
                Button {
                    let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                    NSWorkspace.shared.open(downloadsURL)
                } label: {
                    Label("Open Folder", systemImage: "arrow.up.forward.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.effectiveAccentColor)
            }
            .padding(.horizontal, 4)

            ForEach(tracker.active) { item in
                ActiveDownloadRow(item: item, theme: theme)
            }

            if files.isEmpty && tracker.active.isEmpty {
                Text("No downloads found")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .padding()
            } else {
                ForEach(files, id: \.self) { fileURL in
                    DownloadItemRow(fileURL: fileURL, theme: theme)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Boosts (Styles) List View

    private var visibleBoosts: [PageMod] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = browserState.styles.sorted { $0.domain < $1.domain }
        return q.isEmpty ? sorted : sorted.filter { $0.domain.lowercased().contains(q) }
    }

    private func boostSummary(_ style: PageMod) -> String {
        var parts: [String] = []
        if !style.zappedSelectors.isEmpty { parts.append("\(style.zappedSelectors.count) hidden") }
        if !style.customCSS.isEmpty { parts.append("CSS") }
        if !style.customJS.isEmpty { parts.append("JS") }
        if !style.compiledCSS.isEmpty && parts.isEmpty { parts.append("Look") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }

    private var boostsListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            let items = visibleBoosts
            if items.isEmpty {
                Text(browserState.styles.isEmpty
                     ? "No site boosts yet. Open a site and choose Boost from the site controls."
                     : "No matching boosts")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .padding()
            } else {
                ForEach(items) { style in
                    HStack {
                        // The tap-to-edit gesture covers only this text area, so the switch beside it never opens the editor.
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.domain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.foregroundColor)
                                Text(boostSummary(style))
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.secondaryForegroundColor)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingBoostID = style.id }
                        Toggle("", isOn: Binding(
                            get: { style.isEnabled },
                            set: { browserState.setBoostEnabled(id: style.id, enabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(theme.pillBackground))
                    .contextMenu {
                        Button("Edit Boost…") { editingBoostID = style.id }
                        Button("Open Site") {
                            browserState.openNewTab(urlString: "https://\(style.domain)")
                            closeLibrary()
                        }
                        Divider()
                        Button("Delete Boost", role: .destructive) {
                            browserState.deleteBoost(id: style.id)
                        }
                    }
                }
            }
        }
        .padding(8)
        .sheet(isPresented: Binding(
            get: { editingBoostID != nil },
            set: { if !$0 { editingBoostID = nil } }
        )) {
            if let id = editingBoostID {
                LibraryBoostEditorView(boostID: id)
                    .environmentObject(browserState)
            }
        }
    }

    // MARK: - Media List View

    private var visibleMedia: [URL] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return mediaFiles }
        return mediaFiles.filter { $0.lastPathComponent.lowercased().contains(q) }
    }

    private var mediaListView: some View {
        let items = visibleMedia
        return Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.secondaryForegroundColor)
                    Text("No media found")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryForegroundColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], spacing: 6) {
                    ForEach(items, id: \.self) { url in
                        MediaTile(fileURL: url, theme: theme)
                    }
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Archived Tab Row Item

struct ArchivedTabRowItem: View {
    let tab: ArchivedTab
    let theme: SpaceTheme
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                if let fav = FaviconCache.shared.favicon(for: tab.urlString) {
                    Image(nsImage: fav)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: 16, height: 16)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title.isEmpty ? tab.urlString : tab.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.foregroundColor)
                        .lineLimit(1)

                    Text(cleanHostOrPath(tab.urlString))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? theme.hoverBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func cleanHostOrPath(_ urlStr: String) -> String {
        guard let url = URL(string: urlStr) else { return urlStr }
        let host = url.host ?? ""
        let path = url.path
        if path.count > 1 {
            return host + path
        }
        return host
    }
}

struct DownloadItemRow: View {
    let fileURL: URL
    let theme: SpaceTheme
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileURL.lastPathComponent)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.foregroundColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(fileSizeString)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryForegroundColor)
            }

            Spacer()

            if isHovered {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? theme.hoverBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(fileURL)
        }
    }

    private var fileSizeString: String {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return ""
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: Int64(size))
    }
}

struct ActiveDownloadRow: View {
    let item: DownloadTracker.ActiveDownload
    let theme: SpaceTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFileType: item.fileURL.pathExtension))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileURL.lastPathComponent)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.foregroundColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressView(value: item.fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .tint(theme.effectiveAccentColor)

                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryForegroundColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private var statusText: String {
        let percent = Int((item.fraction * 100).rounded())
        guard item.totalBytes > 0 else { return "Downloading…" }
        let received = ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file)
        return "\(received) of \(total) · \(percent)%"
    }
}

struct MediaTile: View {
    let fileURL: URL
    let theme: SpaceTheme
    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.pillBackground)
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .frame(width: 32, height: 32)
            }
        }
        .frame(height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.effectiveAccentColor.opacity(isHovered ? 0.8 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { NSWorkspace.shared.open(fileURL) }
        .help(fileURL.lastPathComponent)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
        }
        .task(id: fileURL) {
            let url = fileURL
            thumbnail = await Task.detached(priority: .utility) { Self.loadThumbnail(url) }.value
        }
    }

    /// Downsampled decode so large images never get fully inflated for a 78 pt tile.
    nonisolated private static func loadThumbnail(_ url: URL) -> NSImage? {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
