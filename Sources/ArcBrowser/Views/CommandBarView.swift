import SwiftUI

public struct CommandBarView: View {
    @EnvironmentObject var browserState: BrowserState
    @FocusState private var isInputFocused: Bool

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    private var openInCurrentTab: Bool {
        !browserState.commandBarInitialQuery.isEmpty
    }

    struct CommandSuggestion: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        let badge: String
        let action: () -> Void
    }

    public init() {}

    private var suggestions: [CommandSuggestion] {
        var list: [CommandSuggestion] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Primary URL or Web Search action
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

        // 2. Matching Existing Tabs across Spaces ("Switch to Tab")
        let allTabs = browserState.favorites + browserState.spaces.flatMap { $0.allTabs }
        let matchingTabs = allTabs.filter { tab in
            guard !lower.isEmpty else { return true }
            return tab.displayTitle.lowercased().contains(lower) || tab.urlString.lowercased().contains(lower)
        }

        for tab in matchingTabs.prefix(trimmed.isEmpty ? 4 : 6) {
            list.append(
                CommandSuggestion(
                    icon: tab.isFavorite ? "star.fill" : (tab.isPinned ? "pin.fill" : "macwindow"),
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

        // 3. Built-in Arc Commands
        let actions: [(keywords: String, icon: String, title: String, subtitle: String, badge: String, run: () -> Void)] = [
            ("split view pane dual", "rectangle.split.2x1", "Add Split View", "Open a side-by-side pane in current Space", "⌃⇧=", {
                browserState.isCommandBarPresented = false
                browserState.addSplitPane()
            }),
            ("easel board canvas draw", "scribble.variable", "New Arc Easel", "Create a visual canvas for notes, captures & links", "Action", {
                browserState.isCommandBarPresented = false
                browserState.createNewEasel(title: trimmed.isEmpty ? "Untitled Easel" : trimmed)
            }),
            ("note markdown text", "note.text.badge.plus", "New Arc Note", "Create a distraction-free note in your sidebar", "Action", {
                browserState.isCommandBarPresented = false
                browserState.createNewNote(title: trimmed.isEmpty ? "Quick Note" : trimmed)
            }),
            ("hibernate memory ram sleep unload", "moon.zzz.fill", "Hibernate Background Tabs (0 MB RAM)", "Unload all inactive WebViews to minimize system memory", "Memory", {
                browserState.isCommandBarPresented = false
                Task { await browserState.hibernateAllBackgroundTabsNow() }
            }),
            ("boost css zapper customize style", "bolt.fill", "Create / Edit Arc Boost", "Customize colors, fonts, CSS, or zap page elements", "Boost", {
                browserState.isCommandBarPresented = false
                browserState.isBoostStudioPresented = true
            }),
            ("ask ai max claude summarize page", "sparkles", "Arc Max: Ask on Page (Claude / OCI)", "Ask questions or summarize the active webpage", "⌘F", {
                browserState.isCommandBarPresented = false
                browserState.isFindAndAskBarPresented = true
            }),
            ("tidy organize sort tabs", "wand.and.stars", "Arc Max: Tidy Today Tabs", "Automatically group Today tabs into clean sections", "Arc Max", {
                browserState.isCommandBarPresented = false
                browserState.tidyTodayTabs()
            }),
            ("theme color gradient grain space", "paintpalette.fill", "Customize Space Theme", "Adjust gradient colors, vibrancy, and grain texture", "Theme", {
                browserState.isCommandBarPresented = false
                browserState.isThemePickerPresented = true
            }),
            ("sync oci cloud backup server", "icloud.and.arrow.up", "Sync Sidebar & Easels to OCI Box", "Backup state to \(browserState.ociConfig.sshHostAlias):~/.arc2-cloud", "Cloud", {
                browserState.isCommandBarPresented = false
                Task { await browserState.syncToOCICloudNow() }
            }),
            ("import arc browser storable sidebar", "arrow.down.doc.fill", "Import Spaces & Tabs from Arc.app", "Import StorableSidebar.json from installed Arc Browser", "Import", {
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
            // Backdrop dim
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture {
                    browserState.isCommandBarPresented = false
                }

            VStack(spacing: 0) {
                // Input Row
                HStack(spacing: 12) {
                    Image(systemName: openInCurrentTab ? "globe" : "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(browserState.activeTheme.accentColor.swiftUIColor)

                    TextField("Search or Enter URL...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($isInputFocused)
                        .onSubmit {
                            executeSelectedOrSubmit()
                        }
                        .onChange(of: query) { _, _ in
                            selectedIndex = 0
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(openInCurrentTab ? "Current Tab" : "New Tab")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                Divider()
                    .overlay(Color.white.opacity(0.12))

                // Suggestions List
                VStack(spacing: 3) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, item in
                        let isSelected = idx == selectedIndex
                        Button {
                            item.action()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white : browserState.activeTheme.accentColor.swiftUIColor)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white.opacity(isSelected ? 0.22 : 0.08))
                                    )

                                VStack(alignment: .leading, spacing: 1.5) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    Text(item.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.58))
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(item.badge)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.55))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(isSelected ? 0.20 : 0.07))
                                    )
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? browserState.activeTheme.primaryColor.swiftUIColor.opacity(0.55) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(width: 640)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.09, green: 0.09, blue: 0.12).opacity(0.94))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    browserState.activeTheme.primaryColor.swiftUIColor.opacity(0.28),
                                    browserState.activeTheme.secondaryColor.swiftUIColor.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 36, y: 18)
            .padding(.bottom, 120)
        }
        .onAppear {
            query = browserState.commandBarInitialQuery
            selectedIndex = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                isInputFocused = true
            }
        }
        .onKeyPress(.upArrow) {
            if !suggestions.isEmpty {
                selectedIndex = (selectedIndex - 1 + suggestions.count) % suggestions.count
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !suggestions.isEmpty {
                selectedIndex = (selectedIndex + 1) % suggestions.count
            }
            return .handled
        }
        .onKeyPress(.escape) {
            browserState.isCommandBarPresented = false
            return .handled
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
