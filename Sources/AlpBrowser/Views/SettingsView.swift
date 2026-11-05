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
    @ObservedObject private var extensionManager = AlpExtensionManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab: SettingsTab = .general
    @State private var webStoreInput: String = ""
    @State private var confirmRestore = false
    @State private var confirmReplaceCloud = false

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
            case .sync: return "icloud.and.arrow.up"
            case .privacy: return "shield.lefthalf.filled"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar Row — all 5 tabs + Done button fit cleanly with room to spare
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    let isSelected = (selectedTab == tab)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                            Text(tab.rawValue)
                                .lineLimit(1)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.20) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 12)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
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
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 720, height: 590)
    }

    // MARK: - 1. General & App Icons Tab

    private var generalAndIconsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("App Icon")
                    .font(.system(size: 14, weight: .bold))

                Text("Choose an official icon or create your own with the custom studio. Single-click applies instantly to Dock and Finder.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // 3 App Icon Cards — stretch equally across the full horizontal width
            HStack(spacing: 14) {
                // Original Dark Icon: "Après-ski"
                IconChoiceCard(
                    title: "Après-ski",
                    subtitle: "Dark Slate",
                    iconName: "alp_browser_original",
                    isSelected: browserState.selectedIconName == "alp_browser_original"
                ) {
                    browserState.selectAppIcon(named: "alp_browser_original")
                }

                // Light / White Icon: "Kumori-nashi"
                IconChoiceCard(
                    title: "Kumori-nashi",
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
            .frame(maxWidth: .infinity)

            // Custom Icon Studio Box (Full width)
            customIconStudioBox

            Divider().padding(.vertical, 2)

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
                .frame(width: 140)
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
                .frame(width: 140)
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

            // Presets Row (expands evenly across full width)
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

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
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Controls (full width)
            VStack(spacing: 11) {
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
                    .frame(width: 260)

                    if browserState.customIconConfig.bgMode == 2 {
                        ColorPicker("Background Color", selection: bgColorBinding)
                            .labelsHidden()
                    }

                    Spacer()
                }

                // Grain Slider (stretches across remaining width)
                HStack(spacing: 12) {
                    Text("Texture Grain:")
                        .font(.system(size: 12))
                        .frame(width: 120, alignment: .leading)

                    Slider(value: grainBinding, in: 0.0...1.0)
                        .frame(maxWidth: .infinity)

                    Text(String(format: "%.0f%%", browserState.customIconConfig.grain * 100))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
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
                            Text(browserState.customIconConfig.customImagePath != nil ? "Replace Image..." : "Choose Image File...")
                        }
                    }
                    .controlSize(.small)

                    if let path = browserState.customIconConfig.customImagePath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 180)

                        Button("Reset to Mountain") {
                            browserState.resetCustomIconToMountain()
                        }
                        .controlSize(.small)
                    }

                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

    // MARK: - 2. Appearance Tab (space style editor)

    private var appearanceTab: some View {
        SpaceThemeStudioView()
    }

    // MARK: - 3. Vault Sync Tab (Clean Consumer Experience — Zero Endpoint Plumbing)

    private var syncTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Security Guarantee Card
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("End-to-End Encrypted Vault")
                        .font(.system(size: 14, weight: .bold))
                    Text("Your spaces, pinned tabs, folders, easels, notes, and boosts are sealed on this Mac with AES-256-GCM authenticated encryption. Zero browsing history or unencrypted data ever leaves your device.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Sync Status & Automatic Toggle Card
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(browserState.syncProblem == nil ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(cleanSyncHeadline)
                            .font(.system(size: 13, weight: .semibold))

                        if let problem = browserState.syncProblem {
                            Text(problem)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let lastSync = browserState.syncConfig.lastSyncedAt {
                            Text("Last updated \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("All spaces and tabs are protected in your encrypted vault")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text("AES-256-GCM")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Divider()

                Toggle("Automatically back up changes in the background", isOn: $browserState.syncConfig.autoSyncEnabled)
                    .font(.system(size: 12.5))
                    .onChange(of: browserState.syncConfig.autoSyncEnabled) { _, _ in browserState.scheduleSave() }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.8)
            )

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    Task {
                        await browserState.syncNow()
                    }
                } label: {
                    Label("Sync Vault Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    confirmRestore = true
                } label: {
                    Label("Restore from Backup", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                if browserState.syncHasConflict {
                    Button {
                        confirmReplaceCloud = true
                    } label: {
                        Label("Replace Cloud Copy", systemImage: "icloud.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else if browserState.syncProblem != nil {
                    Button {
                        Task { await browserState.restoreVaultFromLocalBackup() }
                    } label: {
                        Label("Restore from This Mac", systemImage: "internaldrive")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer()
            }
            .confirmationDialog("Restore tabs and spaces from the backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restore", role: .destructive) {
                    Task { await browserState.restoreVaultFromCloud() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces the spaces, tabs, easels and notes on this Mac with the backup. A safety copy of what is here now is saved first.")
            }
            .confirmationDialog("Replace the cloud copy with this device?", isPresented: $confirmReplaceCloud, titleVisibility: .visible) {
                Button("Replace Cloud Copy", role: .destructive) {
                    Task { await browserState.syncNow(overwriteRemote: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Changes made on another device that are only in the cloud copy will be lost.")
            }
        }
    }

    private var cleanSyncHeadline: String {
        let raw = browserState.syncStatusText
        if raw.lowercased().contains("syncing") {
            return "Syncing Encrypted Vault…"
        }
        if raw.lowercased().contains("restoring") {
            return "Restoring Encrypted Vault…"
        }
        if browserState.syncProblem != nil {
            return browserState.syncHasConflict ? "Sync Paused: Cloud Vault Changed" : "Saved on This Mac Only"
        }
        return "Encrypted Vault Active"
    }

    // MARK: - 4. Privacy & Shields Tab

    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Privacy & Ad Blocking Shields")
                .font(.system(size: 14, weight: .bold))

            Toggle("Enable Native Bytecode Ad & Tracker Blocker", isOn: $browserState.adBlockerEnabled)
                .font(.system(size: 12.5, weight: .medium))
                .onChange(of: browserState.adBlockerEnabled) { _, enabled in
                    WebViewPool.shared.setAdBlockerEnabled(enabled)
                    browserState.scheduleSave()
                }

            Text("Blocks known analytics scripts, cross-site trackers, and advertising telemetry via WKContentRuleList without slowing down page load performance.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Text("Transition from Arc Browser")
                .font(.system(size: 14, weight: .bold))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Spaces, Pinned Tabs, Themes & Extensions from Arc")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Imports your local StorableSidebar.json and installed extensions directly from Arc.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Import from Arc") {
                    browserState.importFromInstalledArcBrowser()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private func installFromWebStore() {
        let input = webStoreInput
        Task {
            if await extensionManager.installFromWebStore(input) {
                webStoreInput = ""
                browserState.showToast("Extension installed")
            }
        }
    }

    // MARK: - 5. Web Extensions Tab (with automatic extension import)

    private var extensionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Extensions")
                        .font(.system(size: 15, weight: .bold))
                    Text("Extensions imported from Arc Browser and custom unpacked extensions.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let count = extensionManager.importExtensionsFromArc(silent: false)
                    browserState.showToast(count > 0 ? "Imported \(count) new extensions from Arc" : "All \(extensionManager.installedExtensions.count) Arc extensions up to date")
                } label: {
                    Label("Import from Arc", systemImage: "arrow.down.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await extensionManager.installExtensionFromOpenPanel()
                    }
                } label: {
                    Label("Load Unpacked…", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                TextField("Chrome Web Store link or extension ID", text: $webStoreInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { installFromWebStore() }
                Button("Install") { installFromWebStore() }
                    .buttonStyle(.bordered)
                    .disabled(webStoreInput.trimmingCharacters(in: .whitespaces).isEmpty || extensionManager.isExtensionLoading)
            }

            if let errorMsg = extensionManager.lastErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMsg)
                        .font(.system(size: 12))
                    Spacer()
                    Button("Dismiss") {
                        extensionManager.lastErrorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if extensionManager.installedExtensions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No Extensions Installed")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Click 'Import from Arc' to bring over your Arc extensions or 'Load Unpacked…' to select a folder containing a manifest.json.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 8) {
                    ForEach(extensionManager.installedExtensions) { ext in
                        HStack(spacing: 12) {
                            Group {
                                if let nsImg = ext.iconImage {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Image(systemName: "puzzlepiece.extension.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(ext.isEnabled ? Color.accentColor : Color.secondary)
                                        .frame(width: 28, height: 28)
                                }
                            }
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.10))
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ext.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("v\(ext.version)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                if !ext.description.isEmpty {
                                    Text(ext.description)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { ext.isEnabled },
                                set: { _ in
                                    Task {
                                        await extensionManager.toggleExtension(id: ext.id)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()

                            Button {
                                Task {
                                    await extensionManager.removeExtension(id: ext.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove Extension")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.secondary.opacity(0.06))
                        )
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
                    .frame(width: 62, height: 62)
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 3)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10.5))
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : (isHovered ? Color.secondary.opacity(0.10) : Color.secondary.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.14), lineWidth: isSelected ? 1.6 : 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var iconImage: NSImage {
        if let customImage = customImage {
            return customImage
        }
        if let img = AlpIconGenerator.bundledIcon(named: iconName) {
            return img
        }
        return NSApp.applicationIconImage ?? NSImage()
    }
}
