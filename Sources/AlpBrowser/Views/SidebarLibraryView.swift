//
//  SidebarLibraryView.swift
//  Alp Browser
//
//  In-Sidebar Dual-Column Library view matching Arc.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI

public enum LibraryRailSection: String, CaseIterable, Identifiable {
    case media = "Media"
    case downloads = "Downloads"
    case canvases = "Canvases"
    case spaces = "Spaces"
    case styles = "Styles"
    case archive = "Archived Tabs"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .downloads: return "arrow.down.circle"
        case .canvases: return "pencil.tip.crop.circle"
        case .spaces: return "square.3.layers.3d"
        case .styles: return "sparkles"
        case .archive: return "archivebox"
        }
    }
}

public struct SidebarLibraryView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var selectedSection: LibraryRailSection = .archive
    @State private var searchQuery: String = ""
    @State private var downloadFiles: [URL] = []
    @State private var archiveFilter: ArchiveFilter = .all

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
            // Left Rail Column (Arc: no divider, items vertically centred)
            railColumn
                .frame(width: 74)

            // Right Content Sub-panel
            contentColumn
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.foregroundColor)
        .onAppear {
            Self.setWindowTrafficLights(hidden: true)
            reloadDownloads()
        }
        .onChange(of: selectedSection) { _, _ in
            searchQuery = ""
            if selectedSection == .downloads { reloadDownloads() }
        }
        .onDisappear { Self.setWindowTrafficLights(hidden: false) }
    }

    /// Arc hides the window's traffic lights while the Library occupies the sidebar.
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

            // Bottom: back to sidebar + invite (matches Arc's ← and gift)
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
                case .canvases:
                    canvasesListView
                case .downloads:
                    downloadsListView
                case .styles:
                    stylesListView
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
        case .canvases: return "Search Canvases..."
        case .downloads: return "Search Downloads..."
        case .styles: return "Search Styles..."
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
            }
        }
    }

    // MARK: - Canvases List View

    private var canvasesListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if browserState.canvases.isEmpty {
                Text("No canvases yet")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .padding()
            } else {
                ForEach(browserState.canvases) { canvas in
                    Button {
                        browserState.openNewTab(
                            urlString: "alp://canvas/\(canvas.id)",
                            title: canvas.title,
                            kind: .canvas(canvas.id)
                        )
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            browserState.isLibrarySheetPresented = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.and.outline")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.effectiveAccentColor)
                            Text(canvas.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.foregroundColor)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.hoverBackground.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
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
        DispatchQueue.global(qos: .userInitiated).async {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
            let files = (try? FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let dated: [(URL, Date)] = files.compactMap { url in
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
                return (url, v.contentModificationDate ?? .distantPast)
            }
            let sorted = dated.sorted { $0.1 > $1.1 }.prefix(100).map { $0.0 }
            DispatchQueue.main.async { downloadFiles = Array(sorted) }
        }
    }

    private var recentDownloads: [URL] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(downloadFiles.prefix(25))
        }
        let q = searchQuery.lowercased()
        return downloadFiles.filter { $0.lastPathComponent.lowercased().contains(q) }
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

            if files.isEmpty {
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

    // MARK: - Styles List View

    private var stylesListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if browserState.styles.isEmpty {
                Text("No custom site styles created yet")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .padding()
            } else {
                ForEach(browserState.styles) { style in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.domain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.foregroundColor)
                            Text("\(style.zappedSelectors.count) hidden elements")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.secondaryForegroundColor)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { style.isEnabled },
                            set: { val in
                                if let idx = browserState.styles.firstIndex(where: { $0.id == style.id }) {
                                    browserState.styles[idx].isEnabled = val
                                    browserState.scheduleSave()
                                }
                            }
                        ))
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(theme.pillBackground))
                }
            }
        }
        .padding(8)
    }

    // MARK: - Media List View

    private var mediaListView: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(theme.secondaryForegroundColor)
            Text("No recent media saved")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryForegroundColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
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
