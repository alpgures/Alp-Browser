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
        case extensions = "Extensions"
        case sync = "Vault Sync"
        case privacy = "Privacy & Shields"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .general: return "app.badge"
            case .appearance: return "paintpalette"
            case .extensions: return "puzzlepiece.extension"
            case .sync: return "arrow.triangle.2.circlepath"
            case .privacy: return "shield.lefthalf.filled"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // macOS style toolbar row
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalAndIconsTab
                    case .appearance:
                        appearanceTab
                    case .extensions:
                        extensionsTab
                    case .sync:
                        syncTab
                    case .privacy:
                        privacyTab
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 650, maxWidth: 740, minHeight: 500, maxHeight: 680)
    }

    // MARK: - 1. General & App Icons Tab

    private var generalAndIconsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("App Icon")
                .font(.system(size: 14, weight: .bold))

            Text("Choose an official icon or create your own with the custom studio. Single-click applies instantly to Dock and Finder.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // 3 App Icon Cards
            HStack(spacing: 16) {
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

                // Custom Studio Icon
                IconChoiceCard(
                    title: "Custom Studio",
                    subtitle: browserState.customIconConfig.customImagePath != nil ? "Custom Image" : "Gradient & Grain",
                    iconName: "custom",
                    customImage: customIconPreview,
                    isSelected: browserState.selectedIconName == "custom"
                ) {
                    browserState.selectAppIcon(named: "custom")
                }
            }

            // Custom Icon Studio Box
            customIconStudioBox

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

    // MARK: - Custom Icon Studio Box

    private var customIconStudioBox: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom Icon Studio")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Personalize mountain gradient, texture grain, background style, or load any custom image.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if browserState.selectedIconName == "custom" {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Active Icon")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Button("Apply as Icon") {
                        browserState.selectAppIcon(named: "custom")
                    }
                    .controlSize(.small)
                }
            }

            // Presets
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AlpIconGenerator.presets) { preset in
                            Button {
                                var config = browserState.customIconConfig
                                config.startColorHex = preset.startHex
                                config.endColorHex = preset.endHex
                                config.bgMode = preset.bgMode
                                config.grain = preset.grain
                                config.customImagePath = nil
                                browserState.updateCustomIconConfig(config)
                                browserState.selectAppIcon(named: "custom")
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    RGBAColor(hex: preset.startHex)?.swiftUIColor ?? .orange,
                                                    RGBAColor(hex: preset.endHex)?.swiftUIColor ?? .purple
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 12, height: 12)
                                    Text(preset.name)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.secondary.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            // Controls
            VStack(spacing: 10) {
                // Gradient Pickers
                HStack {
                    Text("Logo Gradient:")
                        .font(.system(size: 12))
                        .frame(width: 120, alignment: .leading)

                    ColorPicker("Start", selection: startColorBinding)
                        .labelsHidden()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    ColorPicker("End", selection: endColorBinding)
                        .labelsHidden()

                    Text("\(browserState.customIconConfig.startColorHex) → \(browserState.customIconConfig.endColorHex)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                // Background Style
                HStack {
                    Text("Background:")
                        .font(.system(size: 12))
                        .frame(width: 120, alignment: .leading)

                    Picker("", selection: bgModeBinding) {
                        Text("Dark").tag(0)
                        Text("Light").tag(1)
                        Text("Custom Color").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)

                    if browserState.customIconConfig.bgMode == 2 {
                        ColorPicker("Background Color", selection: bgColorBinding)
                            .labelsHidden()
                    }

                    Spacer()
                }

                // Grain Slider
                HStack {
                    Text("Texture Grain:")
                        .font(.system(size: 12))
                        .frame(width: 120, alignment: .leading)

                    Slider(value: grainBinding, in: 0.0...1.0)
                        .frame(width: 200)

                    Text(String(format: "%.0f%%", browserState.customIconConfig.grain * 100))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)

                    Spacer()
                }

                // Custom Graphic / File Upload
                HStack {
                    Text("Custom Graphic:")
                        .font(.system(size: 12))
                        .frame(width: 120, alignment: .leading)

                    Button {
                        chooseCustomImageFile()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.badge.plus")
                            Text(browserState.customIconConfig.customImagePath != nil ? "Replace File..." : "Choose Image File...")
                        }
                    }
                    .controlSize(.small)

                    if let path = browserState.customIconConfig.customImagePath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 140)

                        Button("Reset to Mountain") {
                            browserState.resetCustomIconToMountain()
                        }
                        .controlSize(.small)
                    }

                    Spacer()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.8)
        )
    }

    private var customIconPreview: NSImage {
        AlpIconGenerator.generateCustomIcon(config: browserState.customIconConfig)
            ?? AlpIconGenerator.loadCustomIconFromDisk()
            ?? NSApp.applicationIconImage
            ?? NSImage()
    }

    private var startColorBinding: Binding<Color> {
        Binding(
            get: {
                RGBAColor(hex: browserState.customIconConfig.startColorHex)?.swiftUIColor ?? Color.orange
            },
            set: { newColor in
                if let hex = extractHex(from: newColor) {
                    var config = browserState.customIconConfig
                    config.startColorHex = hex
                    browserState.updateCustomIconConfig(config)
                }
            }
        )
    }

    private var endColorBinding: Binding<Color> {
        Binding(
            get: {
                RGBAColor(hex: browserState.customIconConfig.endColorHex)?.swiftUIColor ?? Color.purple
            },
            set: { newColor in
                if let hex = extractHex(from: newColor) {
                    var config = browserState.customIconConfig
                    config.endColorHex = hex
                    browserState.updateCustomIconConfig(config)
                }
            }
        )
    }

    private var bgColorBinding: Binding<Color> {
        Binding(
            get: {
                RGBAColor(hex: browserState.customIconConfig.bgColorHex)?.swiftUIColor ?? Color.black
            },
            set: { newColor in
                if let hex = extractHex(from: newColor) {
                    var config = browserState.customIconConfig
                    config.bgColorHex = hex
                    browserState.updateCustomIconConfig(config)
                }
            }
        )
    }

    private var grainBinding: Binding<Double> {
        Binding(
            get: { browserState.customIconConfig.grain },
            set: { newGrain in
                var config = browserState.customIconConfig
                config.grain = newGrain
                browserState.updateCustomIconConfig(config)
            }
        )
    }

    private var bgModeBinding: Binding<Int> {
        Binding(
            get: { browserState.customIconConfig.bgMode },
            set: { newMode in
                var config = browserState.customIconConfig
                config.bgMode = newMode
                browserState.updateCustomIconConfig(config)
            }
        )
    }

    private func extractHex(from color: Color) -> String? {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(round(max(0, min(1, ns.redComponent)) * 255))
        let g = Int(round(max(0, min(1, ns.greenComponent)) * 255))
        let b = Int(round(max(0, min(1, ns.blueComponent)) * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func chooseCustomImageFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Custom Icon Image"
        panel.prompt = "Set as Icon"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .icns, .image]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                browserState.selectCustomIconImage(url: url)
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

    // MARK: - 5. Web Extensions Tab

    private var extensionsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Web Extensions")
                        .font(.system(size: 15, weight: .bold))
                    Text("Load unpacked Safari and Chrome Manifest V3 extensions into Alp Browser.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await AlpExtensionManager.shared.installExtensionFromOpenPanel()
                    }
                } label: {
                    Label("Install Extension...", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMsg = AlpExtensionManager.shared.lastErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMsg)
                        .font(.system(size: 12))
                    Spacer()
                    Button("Dismiss") {
                        AlpExtensionManager.shared.lastErrorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if AlpExtensionManager.shared.installedExtensions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No Extensions Installed")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Click 'Install Extension...' to load any unpacked directory containing a manifest.json.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 10) {
                    ForEach(AlpExtensionManager.shared.installedExtensions) { ext in
                        HStack(spacing: 12) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(ext.isEnabled ? Color.accentColor : Color.secondary)
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ext.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("v\(ext.version)")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                                if !ext.description.isEmpty {
                                    Text(ext.description)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { ext.isEnabled },
                                set: { _ in
                                    Task {
                                        await AlpExtensionManager.shared.toggleExtension(id: ext.id)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()

                            Button {
                                Task {
                                    await AlpExtensionManager.shared.removeExtension(id: ext.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove Extension")
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
}

struct IconChoiceCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    var customImage: NSImage? = nil
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
        if let customImage = customImage {
            return customImage
        }
        let path = Bundle.main.path(forResource: iconName, ofType: "icns")
            ?? "/Users/alpgures/Documents/antigravity/arc2.0/Icons/\(iconName).icns"
        if let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSApp.applicationIconImage ?? NSImage()
    }
}
