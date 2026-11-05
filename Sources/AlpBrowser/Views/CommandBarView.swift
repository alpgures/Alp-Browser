//
//  CommandBarView.swift
//  Alp Browser
//
//  Floating Command Bar (⌘T / ⌘L) for navigation, searches, and actions.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI

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
        let subtitle: String
        let badge: String
        let action: () -> Void

        init(icon: String, favicon: NSImage? = nil, title: String, subtitle: String, badge: String, action: @escaping () -> Void) {
            self.icon = icon
            self.favicon = favicon
            self.title = title
            self.subtitle = subtitle
            self.badge = badge
            self.action = action
        }
    }

    public init() {}

    private var suggestions: [CommandSuggestion] {
        var list: [CommandSuggestion] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Primary URL or Web Search Action
        if !trimmed.isEmpty {
            let isLikelyURL = !trimmed.contains(" ") && (trimmed.contains(".") || trimmed.hasPrefix("http") || trimmed.hasPrefix("localhost"))
            list.append(
                CommandSuggestion(
                    icon: isLikelyURL ? "globe" : "magnifyingglass",
                    title: isLikelyURL ? "Open \(trimmed)" : "Search Google for “\(trimmed)”",
                    subtitle: isLikelyURL ? browserState.resolveInputToURLString(trimmed) : "Google Search",
                    badge: openInCurrentTab ? "Navigate ↵" : "New Tab ↵",
                    action: {
                        browserState.handleCommandBarInput(trimmed, openInNewTab: !openInCurrentTab)
                    }
                )
            )
        }

        // 2. Open Tabs Matching Query ("Switch to Tab")
        let allTabs = browserState.favorites + browserState.spaces.flatMap { $0.allTabs }
        let matchingTabs = allTabs.filter { tab in
            guard !lower.isEmpty else { return true }
            return tab.displayTitle.lowercased().contains(lower) || tab.urlString.lowercased().contains(lower)
        }

        for tab in matchingTabs.prefix(trimmed.isEmpty ? 5 : 7) {
            let fav = FaviconCache.shared.favicon(for: tab.urlString)
            list.append(
                CommandSuggestion(
                    icon: tab.isFavorite ? "star.fill" : (tab.isPinned ? "pin.fill" : "globe"),
                    favicon: fav,
                    title: tab.displayTitle,
                    subtitle: tab.simplifiedDomain,
                    badge: "Switch to Tab",
                    action: {
                        browserState.selectTab(tab.id)
                        browserState.isCommandBarPresented = false
                    }
                )
            )
        }

        // 3. Built-in Alp Browser Actions
        let actions: [(keywords: String, icon: String, title: String, subtitle: String, badge: String, run: () -> Void)] = [
            ("split view pane side", "rectangle.split.2x1", "Add Split View", "Open side-by-side pane in active Space", "⌃⇧=", {
                browserState.isCommandBarPresented = false
                browserState.addSplitPane()
            }),
            ("canvas board note draw", "scribble.variable", "New Canvas", "Create a visual board for notes and cards", "Action", {
                browserState.isCommandBarPresented = false
                browserState.createNewCanvas(title: trimmed.isEmpty ? "Untitled Canvas" : trimmed)
            }),
            ("note markdown text editor", "note.text.badge.plus", "New Note", "Create a clean distraction-free note", "Action", {
                browserState.isCommandBarPresented = false
                browserState.createNewNote(title: trimmed.isEmpty ? "Quick Note" : trimmed)
            }),
            ("hibernate memory ram sleep unload", "moon.zzz.fill", "Hibernate Background Tabs (0 MB RAM)", "Unload all inactive WebViews to free memory", "Memory", {
                browserState.isCommandBarPresented = false
                Task { await browserState.hibernateAllBackgroundTabsNow() }
            }),
            ("style css zapper customize mod", "bolt.fill", "Customize Page Style", "Adjust colors, fonts, CSS, or hide page elements", "Style", {
                browserState.isCommandBarPresented = false
                browserState.isStyleStudioPresented = true
            }),
            ("theme color gradient space grain", "paintpalette.fill", "Space Theme Editor", "Change colors, vibrancy, and frosted grain", "Theme", {
                browserState.isCommandBarPresented = false
                browserState.isThemePickerPresented = true
            }),
            ("sync backup vault cloud server", "arrow.triangle.2.circlepath", "Sync Vault Now", "Upload encrypted state to your sync vault", "Sync", {
                browserState.isCommandBarPresented = false
                Task { await browserState.syncNow() }
            }),
            ("import arc browser storable sidebar", "arrow.down.doc.fill", "Import Spaces from Arc", "Import spaces, favorites, and themes from Arc.app", "Import", {
                browserState.isCommandBarPresented = false
                browserState.importFromInstalledArcBrowser()
            })
        ]

        for act in actions {
            if lower.isEmpty || act.keywords.contains(lower) || act.title.lowercased().contains(lower) {
                list.append(
                    CommandSuggestion(
                        icon: act.icon,
                        title: act.title,
                        subtitle: act.subtitle,
                        badge: act.badge,
                        action: act.run
                    )
                )
            }
        }

        return Array(list.prefix(9))
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
                // Search Input Box
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    TextField("Search or Enter URL...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($isInputFocused)
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

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }

                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Color(red: 0.12, green: 0.12, blue: 0.15))

                Divider().background(Color.white.opacity(0.12))

                // Suggestion List
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                            let isSelected = (index == selectedIndex)
                            Button {
                                item.action()
                            } label: {
                                HStack(spacing: 12) {
                                    // Favicon or System Icon
                                    Group {
                                        if let fav = item.favicon {
                                            Image(nsImage: fav)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 16, height: 16)
                                        } else {
                                            Image(systemName: item.icon)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(isSelected ? .white : browserState.activeTheme.accentColor.swiftUIColor)
                                                .frame(width: 16, height: 16)
                                        }
                                    }
                                    .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.6))
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    // Action Badge / Switch to Tab Indicator
                                    if item.badge == "Switch to Tab" {
                                        HStack(spacing: 7) {
                                            Text("Switch to Tab")
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundStyle(isSelected ? .white : .white.opacity(0.40))

                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 9.5, weight: .bold))
                                                .foregroundStyle(isSelected ? Color(red: 0.17, green: 0.45, blue: 0.52) : .white.opacity(0.60))
                                                .frame(width: 17, height: 17)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                        .fill(isSelected ? Color.white : Color.white.opacity(0.10))
                                                )
                                        }
                                    } else {
                                        Text(item.badge)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule()
                                                    .fill(Color.white.opacity(isSelected ? 0.22 : 0.08))
                                            )
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? Color(red: 0.17, green: 0.45, blue: 0.52) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 340)
            }
            .frame(width: 620)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
            .padding(.bottom, 120)
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

    private func executeSelectedOrSubmit() {
        if suggestions.indices.contains(selectedIndex) {
            suggestions[selectedIndex].action()
        } else {
            browserState.handleCommandBarInput(query, openInNewTab: !openInCurrentTab)
        }
    }
}
