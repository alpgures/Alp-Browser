//
//  SpaceThemeStudioView.swift
//  Alp Browser
//
//  Arc-style Space Theme Studio: Single color, dual gradient, 3-stop mesh,
//  intensity slider, noise texture grain dial, appearance toggles, and live preview.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit

public struct SpaceThemeStudioView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var selectedSpaceIndex: Int = 0
    @State private var mode: SpaceThemeMode = .dualGradient

    public init() {}

    private var currentSpace: AlpSpace {
        if browserState.spaces.indices.contains(selectedSpaceIndex) {
            return browserState.spaces[selectedSpaceIndex]
        }
        return browserState.activeSpace
    }

    private var currentTheme: SpaceTheme {
        currentSpace.theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Space Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Space to Customize")
                    .font(.system(size: 13, weight: .bold))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(browserState.spaces.enumerated()), id: \.element.id) { idx, sp in
                            let isCur = (idx == selectedSpaceIndex)
                            Button {
                                selectedSpaceIndex = idx
                                updateModeFromTheme(sp.theme)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(sp.iconEmoji)
                                    Text(sp.title)
                                        .font(.system(size: 12, weight: isCur ? .bold : .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    isCur ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isCur ? Color.accentColor : Color.clear, lineWidth: 1.2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            // 2. Mode Selector (Single Color, Dual Gradient, 3-Stop Mesh)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Theme Style Mode")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(SpaceThemeMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                    .onChange(of: mode) { _, newMode in
                        applyModeChange(newMode)
                    }
                }
            }

            // 3. Color Wells & Hex Controls
            colorControlsSection

            Divider()

            // 4. Arc Sliders (Intensity & Noise Grain)
            VStack(alignment: .leading, spacing: 12) {
                Text("Vibrancy & Texture (Arc Engine)")
                    .font(.system(size: 13, weight: .bold))

                // Intensity Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Color Intensity & Saturation:")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(Int(currentTheme.intensityFactor * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding<Double>(
                            get: { currentTheme.intensityFactor },
                            set: { newVal in
                                mutateCurrentTheme { $0.intensityFactor = newVal }
                            }
                        ),
                        in: 0.05...1.0
                    )
                }

                // Grain Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Tactile Noise Grain Overlay:")
                            .font(.system(size: 12))
                        Spacer()
                        Text("\(Int(currentTheme.grainIntensity * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding<Double>(
                            get: { currentTheme.grainIntensity },
                            set: { newVal in
                                mutateCurrentTheme { $0.grainIntensity = newVal }
                            }
                        ),
                        in: 0.0...1.0
                    )
                }

                // Appearance & Translucency Toggles
                HStack(spacing: 24) {
                    Toggle("Dark Appearance (Light Text)", isOn: Binding<Bool>(
                        get: { currentTheme.prefersLightForeground },
                        set: { newVal in mutateCurrentTheme { $0.prefersLightForeground = newVal } }
                    ))
                    .font(.system(size: 12))

                    Toggle("Frosted Glass Vibrancy", isOn: Binding<Bool>(
                        get: { currentTheme.isVibrant },
                        set: { newVal in mutateCurrentTheme { $0.isVibrant = newVal } }
                    ))
                    .font(.system(size: 12))
                }
                .padding(.top, 4)
            }

            Divider()

            // 5. Presets Gallery & Live Space Preview
            HStack(alignment: .top, spacing: 20) {
                // Presets list
                VStack(alignment: .leading, spacing: 8) {
                    Text("Curated Presets")
                        .font(.system(size: 13, weight: .bold))

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(SpaceTheme.presets, id: \.name) { preset in
                                Button {
                                    applyPreset(preset.theme)
                                } label: {
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: preset.theme.renderedGradientColors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 32, height: 22)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.12), lineWidth: 0.6))

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(preset.name)
                                                .font(.system(size: 11.5, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(preset.subtitle)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                .frame(maxWidth: .infinity)

                // Live Preview Box
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Space Preview")
                        .font(.system(size: 13, weight: .bold))

                    liveMiniSidebarPreview
                        .frame(width: 220, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
                .frame(width: 220)
            }
        }
        .onAppear {
            if let activeIdx = browserState.spaces.firstIndex(where: { $0.id == browserState.activeSpaceID }) {
                selectedSpaceIndex = activeIdx
            }
            updateModeFromTheme(currentTheme)
        }
    }

    // MARK: - Color Controls

    private var colorControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color Stops")
                .font(.system(size: 13, weight: .bold))

            HStack(spacing: 16) {
                // Stop 1 / Base Color
                colorStopCard(
                    title: mode == .single ? "Space Color" : "Lead (Top)",
                    color: currentTheme.primaryColor,
                    binding: colorBinding(
                        get: { currentTheme.primaryColor },
                        set: { newCol in
                            mutateCurrentTheme { th in
                                th.primaryColor = newCol
                                if th.colorStops.isEmpty {
                                    th.colorStops = [newCol]
                                } else {
                                    th.colorStops[0] = newCol
                                }
                            }
                        }
                    )
                )

                if mode == .dualGradient || mode == .multiMesh {
                    colorStopCard(
                        title: "Trail (Bottom)",
                        color: currentTheme.secondaryColor,
                        binding: colorBinding(
                            get: { currentTheme.secondaryColor },
                            set: { newCol in
                                mutateCurrentTheme { th in
                                    th.secondaryColor = newCol
                                    if th.colorStops.count >= 2 {
                                        th.colorStops[1] = newCol
                                    } else {
                                        th.colorStops.append(newCol)
                                    }
                                }
                            }
                        )
                    )
                }

                if mode == .multiMesh {
                    colorStopCard(
                        title: "Accent Stop",
                        color: currentTheme.accentColor,
                        binding: colorBinding(
                            get: { currentTheme.accentColor },
                            set: { newCol in
                                mutateCurrentTheme { th in
                                    th.accentColor = newCol
                                    if th.colorStops.count >= 3 {
                                        th.colorStops[2] = newCol
                                    } else {
                                        th.colorStops.append(newCol)
                                    }
                                }
                            }
                        )
                    )
                }
            }
        }
    }

    private func colorStopCard(title: String, color: RGBAColor, binding: Binding<Color>) -> some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: binding)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(color.hexString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: - Live Mini Sidebar Preview

    private var liveMiniSidebarPreview: some View {
        ZStack {
            // Theme Gradient
            LinearGradient(
                colors: currentTheme.renderedGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Mock Sidebar Elements
            VStack(alignment: .leading, spacing: 8) {
                // Window Traffic Lights
                HStack(spacing: 4) {
                    Circle().fill(Color.red.opacity(0.85)).frame(width: 7, height: 7)
                    Circle().fill(Color.yellow.opacity(0.85)).frame(width: 7, height: 7)
                    Circle().fill(Color.green.opacity(0.85)).frame(width: 7, height: 7)
                    Spacer()
                    Text(currentSpace.iconEmoji)
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Space Title
                Text(currentSpace.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(currentTheme.foregroundColor)
                    .padding(.horizontal, 8)

                // Mock URL Bubble
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 8))
                    Text("Search or URL")
                        .font(.system(size: 9))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 8)
                .foregroundStyle(currentTheme.foregroundColor.opacity(0.7))

                // Mock Active Tab
                HStack(spacing: 5) {
                    Circle().fill(currentTheme.effectiveAccentColor).frame(width: 6, height: 6)
                    Text("Antigravity Browser")
                        .font(.system(size: 9, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(currentTheme.selectionBackground, in: RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 8)
                .foregroundStyle(currentTheme.foregroundColor)

                // Mock Inactive Tab
                HStack(spacing: 5) {
                    Image(systemName: "globe").font(.system(size: 7))
                    Text("GitHub — Alp-Browser")
                        .font(.system(size: 9))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .foregroundStyle(currentTheme.secondaryForegroundColor)

                Spacer()
            }
        }
    }

    // MARK: - Mutators & Helpers

    private func colorBinding(get: @escaping () -> RGBAColor, set: @escaping (RGBAColor) -> Void) -> Binding<Color> {
        Binding<Color>(
            get: { get().swiftUIColor },
            set: { newColor in
                set(RGBAColor(color: newColor))
            }
        )
    }

    private func updateModeFromTheme(_ th: SpaceTheme) {
        if th.colorStops.count >= 3 {
            mode = .multiMesh
        } else if th.colorStops.count == 2 {
            mode = .dualGradient
        } else {
            mode = .single
        }
    }

    private func applyModeChange(_ newMode: SpaceThemeMode) {
        mutateCurrentTheme { th in
            switch newMode {
            case .single:
                th.colorStops = [th.primaryColor]
            case .dualGradient:
                th.colorStops = [th.primaryColor, th.secondaryColor]
            case .multiMesh:
                th.colorStops = [th.primaryColor, th.secondaryColor, th.accentColor]
            }
        }
    }

    private func applyPreset(_ presetTheme: SpaceTheme) {
        mutateCurrentTheme { th in
            th = presetTheme
        }
        updateModeFromTheme(presetTheme)
    }

    private func mutateCurrentTheme(_ block: (inout SpaceTheme) -> Void) {
        let idx = min(max(selectedSpaceIndex, 0), max(0, browserState.spaces.count - 1))
        guard browserState.spaces.indices.contains(idx) else { return }
        block(&browserState.spaces[idx].theme)
        browserState.scheduleSave()
    }
}
