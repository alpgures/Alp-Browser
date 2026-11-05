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
    case easels = "Easels"
    case spaces = "Spaces"
    case boosts = "Boosts"
    case archive = "Archived Tabs"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .downloads: return "arrow.down.circle"
        case .easels: return "pencil.tip.crop.circle"
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
        .onAppear { Self.setWindowTrafficLights(hidden: true) }
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
                    Button {
                        // Filter action
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 10.5))
                            Text("Filter")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(theme.secondaryForegroundColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(theme.pillBackground)
                        )
                    }
                    .buttonStyle(.plain)
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
        case .downloads: return "Search Downloads..."
        case .boosts: return "Search Boosts..."
        case .media: return "Search Media..."
        case .spaces: return "Search..."
        }
    }

    // MARK: - Archive List View (Grouped by Today, Yesterday, Previous 7 Days)

    private var filteredArchivedTabs: [ArchivedTab] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return browserState.archivedTabs
        }
        let q = searchQuery.lowercased()
        return browserState.archivedTabs.filter {
            $0.title.lowercased().contains(q) || $0.urlString.lowercased().contains(q)
        }
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

    // MARK: - Easels List View

    private var easelsListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if browserState.canvases.isEmpty {
                Text("No easels yet")
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

    private var recentDownloads: [URL] {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return [] }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        let regularFiles = files.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
        let sorted = regularFiles.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return d1 > d2
        }
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(sorted.prefix(25))
        }
        let q = searchQuery.lowercased()
        return sorted.filter { $0.lastPathComponent.lowercased().contains(q) }
    }

    private var downloadsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if recentDownloads.isEmpty {
                Text("No downloads found")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryForegroundColor)
                    .padding()
            } else {
                ForEach(recentDownloads, id: \.self) { fileURL in
                    DownloadItemRow(fileURL: fileURL, theme: theme)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Boosts (Styles) List View

    private var boostsListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if browserState.styles.isEmpty {
                Text("No custom site boosts created yet")
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
                            Text("\(style.zappedSelectors.count) zapped elements")
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
