//
//  SettingsView.swift
//  Alp Browser
//
//  Clean native macOS Settings window.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit

public struct SettingsView: View {
    @EnvironmentObject var browserState: BrowserState
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab: SettingsTab = .general

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General & Icons"
        case appearance = "Appearance"
        case sync = "Vault Sync"
        case privacy = "Privacy & Shields"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .general: return "app.badge"
            case .appearance: return "paintpalette"
            case .sync: return "arrow.triangle.2.circlepath"
            case .privacy: return "shield.lefthalf.filled"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // macOS style toolbar row
            HStack(spacing: 12) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                        }
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selectedTab == tab ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalAndIconsTab
                    case .appearance:
                        appearanceTab
                    case .sync:
                        syncTab
                    case .privacy:
                        privacyTab
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 580, maxWidth: 640, minHeight: 440, maxHeight: 520)
    }

    // MARK: - 1. General & App Icons Tab

    private var generalAndIconsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("App Icon")
                .font(.system(size: 14, weight: .bold))

            Text("Choose an official icon for Alp Browser. Single-click applies instantly to Dock and Finder.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                // Original Icon
                IconChoiceCard(
                    title: "Alp Original",
                    subtitle: "Dark Slate",
                    iconName: "alp_browser_original",
                    isSelected: browserState.selectedIconName == "alp_browser_original"
                ) {
                    browserState.selectAppIcon(named: "alp_browser_original")
                }

                // White / Light Icon
                IconChoiceCard(
                    title: "Alp Light",
                    subtitle: "Alpine Frost",
                    iconName: "alp_browser_white",
                    isSelected: browserState.selectedIconName == "alp_browser_white"
                ) {
                    browserState.selectAppIcon(named: "alp_browser_white")
                }
            }

            Divider().padding(.vertical, 4)

            Text("Tab & Memory Management")
                .font(.system(size: 14, weight: .bold))

            HStack {
                Text("Auto-archive inactive tabs after:")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: $browserState.autoArchiveHours) {
                    Text("6 Hours").tag(6.0)
                    Text("12 Hours").tag(12.0)
                    Text("24 Hours").tag(24.0)
                    Text("3 Days").tag(72.0)
                }
                .frame(width: 130)
                .onChange(of: browserState.autoArchiveHours) { _, _ in browserState.scheduleSave() }
            }

            HStack {
                Text("Zero-RAM background tab hibernation:")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: $browserState.autoHibernateMinutes) {
                    Text("3 Minutes").tag(3.0)
                    Text("5 Minutes").tag(5.0)
                    Text("15 Minutes").tag(15.0)
                    Text("Never").tag(0.0)
                }
                .frame(width: 130)
                .onChange(of: browserState.autoHibernateMinutes) { _, _ in browserState.scheduleSave() }
            }
        }
    }

    // MARK: - 2. Appearance Tab

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Space Theme Presets")
                .font(.system(size: 14, weight: .bold))

            Text("Select a colorway for your active space. Buttons preview the real theme colors.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(SpaceTheme.presets, id: \.name) { preset in
                    Button {
                        browserState.activeSpace.theme = preset.theme
                        browserState.scheduleSave()
                    } label: {
                        HStack(spacing: 12) {
                            // Actual gradient preview pill
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: preset.theme.renderedGradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 38, height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.15), lineWidth: 0.6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(preset.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            if browserState.activeSpace.theme.primaryColor == preset.theme.primaryColor {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.vertical, 4)

            Toggle("Light Foreground (Dark Appearance)", isOn: $browserState.activeSpace.theme.prefersLightForeground)
                .font(.system(size: 12.5))
                .onChange(of: browserState.activeSpace.theme.prefersLightForeground) { _, _ in
                    browserState.scheduleSave()
                }
        }
    }

    // MARK: - 3. Vault Sync Tab

    private var syncTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Zero-Knowledge Encrypted Vault Sync")
                .font(.system(size: 14, weight: .bold))

            Text("All tabs, spaces, notes, and styles are encrypted on your Mac with AES-256 before upload. Zero personal browsing history or passwords are ever transmitted.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sync Endpoint URL:")
                        .font(.system(size: 12))
                    Spacer()
                    TextField("http://127.0.0.1:8788", text: $browserState.syncConfig.syncEndpointURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onChange(of: browserState.syncConfig.syncEndpointURL) { _, _ in browserState.scheduleSave() }
                }

                HStack {
                    Text("Vault ID:")
                        .font(.system(size: 12))
                    Spacer()
                    TextField("primary", text: $browserState.syncConfig.syncVaultID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onChange(of: browserState.syncConfig.syncVaultID) { _, _ in browserState.scheduleSave() }
                }

                Toggle("Automatically sync changes in background", isOn: $browserState.syncConfig.autoSyncEnabled)
                    .font(.system(size: 12))
                    .onChange(of: browserState.syncConfig.autoSyncEnabled) { _, _ in browserState.scheduleSave() }
            }

            HStack {
                Text("Connection Status: \(browserState.syncStatusText)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(browserState.isSyncConnected ? Color.green : Color.secondary)

                Spacer()

                Button("Sync Vault Now") {
                    Task {
                        await browserState.syncNow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - 4. Privacy & Shields Tab

    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Privacy & Ad Blocking Shields")
                .font(.system(size: 14, weight: .bold))

            Toggle("Enable Native Bytecode Ad & Tracker Blocker", isOn: $browserState.adBlockerEnabled)
                .font(.system(size: 12.5, weight: .medium))
                .onChange(of: browserState.adBlockerEnabled) { _, _ in browserState.scheduleSave() }

            Text("Blocks known analytics scripts, cross-site trackers, and advertising telemetry via WKContentRuleList without slowing down page load performance.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Text("Data Import & Local Profile")
                .font(.system(size: 14, weight: .bold))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Spaces & Pinned Tabs from Arc")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Reads your local StorableSidebar.json into Alp Browser without cloud dependency.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Import Now") {
                    browserState.importFromInstalledArcBrowser()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }
}

struct IconChoiceCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("Active")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                } else {
                    Text("Select")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.1) : Color.secondary.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var iconImage: NSImage {
        let path = Bundle.main.path(forResource: iconName, ofType: "icns")
            ?? "/Users/alpgures/Documents/antigravity/arc2.0/Icons/\(iconName).icns"
        if let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSApp.applicationIconImage ?? NSImage()
    }
}
