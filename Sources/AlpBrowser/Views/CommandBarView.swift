//
//  CommandBarView.swift
//  Alp Browser
//
//  Floating Command Bar (⌘T / ⌘L) matching Arc's single-line layout.
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
        let id = UUID()
        let icon: String
        let favicon: NSImage?
        let title: String
        let isTabSwitch: Bool
        let isActionRow: Bool
        let shortcutBadge: String?
        let action: () -> Void

        init(
            icon: String,
            favicon: NSImage? = nil,
            title: String,
            isTabSwitch: Bool = false,
            isActionRow: Bool = false,
            shortcutBadge: String? = nil,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.favicon = favicon
            self.title = title
            self.isTabSwitch = isTabSwitch
            self.isActionRow = isActionRow
            self.shortcutBadge = shortcutBadge
            self.action = action
        }
    }

    public init() {}

    private var suggestions: [CommandSuggestion] {
        var list: [CommandSuggestion] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Primary URL or Web Search Action when user types
        if !trimmed.isEmpty {
            let isLikelyURL = !trimmed.contains(" ") && (trimmed.contains(".") || trimmed.hasPrefix("http") || trimmed.hasPrefix("localhost") || trimmed.hasPrefix("alp://"))
            list.append(
                CommandSuggestion(
                    icon: isLikelyURL ? "globe" : "magnifyingglass",
                    title: isLikelyURL ? trimmed : "\(trimmed) — Google Search",
                    isTabSwitch: false,
                    isActionRow: false,
                    shortcutBadge: openInCurrentTab ? "Open ↵" : "New Tab ↵",
                    action: {
                        browserState.handleCommandBarInput(trimmed, openInNewTab: !openInCurrentTab)
                    }
                )
            )
        }

        // 2. Open / Pinned Tabs Matching Query ("Switch to Tab") — single-line, skipping extension new-tab placeholders
        var seenTabIDs = Set<UUID>()
        var seenTitles = Set<String>()
        let candidateTabs = (browserState.activeSpace.todayTabs + browserState.activeSpace.pinnedNodes.flatMap { $0.allTabs } + browserState.favorites + browserState.spaces.flatMap { $0.allTabs })
        for tab in candidateTabs {
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

            if !lower.isEmpty {
                let matches = title.lowercased().contains(lower) || urlLower.contains(lower)
                if !matches { continue }
            }

            seenTitles.insert(title.lowercased())
            let fav = FaviconCache.shared.favicon(for: tab.urlString)
            list.append(
                CommandSuggestion(
                    icon: "globe",
                    favicon: fav,
                    title: title,
                    isTabSwitch: true,
                    action: {
                        browserState.selectTab(tab.id)
                        browserState.isCommandBarPresented = false
                    }
                )
            )
            if list.count >= (trimmed.isEmpty ? 4 : 5) {
                break
            }
        }

        // 3. Built-in Actions (Arc shows 1 subtle action row at the bottom when query is empty, or matching actions when typing)
        let actions: [(keywords: String, icon: String, title: String, badge: String?, run: () -> Void)] = [
            ("split view pane side", "rectangle.split.2x1", "Add Split View", "⌃⇧=", {
                browserState.isCommandBarPresented = false
                browserState.addSplitPane()
            }),
            ("easel canvas board draw", "pencil.tip.crop.circle", "New Easel", nil, {
                browserState.isCommandBarPresented = false
                browserState.createNewCanvas(title: trimmed.isEmpty ? "Untitled Easel" : trimmed)
            }),
            ("note markdown text editor", "note.text", "New Note", nil, {
                browserState.isCommandBarPresented = false
                browserState.createNewNote(title: trimmed.isEmpty ? "Quick Note" : trimmed)
            }),
            ("theme color gradient space", "paintpalette", "Edit Space Theme…", nil, {
                browserState.isCommandBarPresented = false
                browserState.isThemePickerPresented = true
            }),
            ("boost style css zapper customize", "wand.and.stars", "New Boost…", nil, {
                browserState.isCommandBarPresented = false
                browserState.isStyleStudioPresented = true
            }),
            ("settings preferences extensions", "gearshape", "Open Settings…", "⌘,", {
                browserState.isCommandBarPresented = false
                browserState.isSettingsPresented = true
            })
        ]

        if lower.isEmpty {
            if let firstAct = actions.first {
                list.append(
                    CommandSuggestion(
                        icon: firstAct.icon,
                        title: firstAct.title,
                        isTabSwitch: false,
                        isActionRow: true,
                        shortcutBadge: nil,
                        action: firstAct.run
                    )
                )
            }
        } else {
            for act in actions {
                if act.keywords.contains(lower) || act.title.lowercased().contains(lower) {
                    list.append(
                        CommandSuggestion(
                            icon: act.icon,
                            title: act.title,
                            isTabSwitch: false,
                            isActionRow: true,
                            shortcutBadge: act.badge,
                            action: act.run
                        )
                    )
                }
            }
        }

        return Array(list.prefix(6))
    }

    /// Selection bar color derived from the active space theme (matching Arc's muted slate-teal highlight)
    private var selectionBarColor: Color {
        let p = browserState.activeTheme.primaryColor
        let blended = p.darkened(by: 0.35).blended(with: RGBAColor(red: 0.21, green: 0.45, blue: 0.52), fraction: 0.55)
        return blended.swiftUIColor
    }

    public var body: some View {
        ZStack {
            // Transparent backdrop: does NOT dim screen, clicking outside dismisses
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    browserState.isCommandBarPresented = false
                }

            VStack(spacing: 0) {
                // Top Search Input Row (Matches Arc: magnifyingglass, query field, info.circle on right)
                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 20, height: 20)

                    TextField("Search or Enter URL...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15.5, weight: .medium))
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

                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Single-line Suggestion Rows (No divider line, fits all rows cleanly without clipping)
                if !suggestions.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                            let isSelected = (index == selectedIndex)
                            Button {
                                item.action()
                            } label: {
                                HStack(spacing: 11) {
                                    // Leading Icon / Favicon Badge (Matches Arc's 20x20 rounded square on selected/action rows)
                                    suggestionIconView(for: item, isSelected: isSelected)

                                    Text(item.title)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(isSelected ? .white : .white.opacity(0.84))
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer(minLength: 12)

                                    // Trailing "Switch to Tab [→]" or Shortcut Badge
                                    if item.isTabSwitch {
                                        HStack(spacing: 8) {
                                            Text("Switch to Tab")
                                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))

                                            Image(systemName: "arrow.right")
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
                                .frame(height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
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
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.095, green: 0.095, blue: 0.105))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 28, y: 12)
            .padding(.bottom, 80)
        }
        .onExitCommand {
            browserState.isCommandBarPresented = false
        }
        .onAppear {
            query = browserState.commandBarInitialQuery
            isInputFocused = true
            selectedIndex = 0

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
