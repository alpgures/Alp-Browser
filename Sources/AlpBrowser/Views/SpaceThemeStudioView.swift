//
//  SpaceThemeStudioView.swift
//  Alp Browser
//
//  Arc-authentic Space Style Editor (SpaceStyleColorPadView + SpaceStyleDialView +
//  Light/Dark/Auto toggle + multi-node gradient pad + live space preview).
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit

public struct SpaceThemeStudioView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var selectedSpaceIndex: Int = 0
    @State private var activeStopIndex: Int = 0

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

    private var effectiveStops: [RGBAColor] {
        let stops = currentTheme.colorStops
        return stops.isEmpty ? [currentTheme.primaryColor] : stops
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Space Selector Header Bar
            HStack(spacing: 10) {
                Text("Space")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(Array(browserState.spaces.enumerated()), id: \.element.id) { idx, sp in
                        let isCur = (idx == selectedSpaceIndex)
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedSpaceIndex = idx
                                activeStopIndex = 0
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(sp.iconEmoji)
                                    .font(.system(size: 13))
                                Text(sp.title)
                                    .font(.system(size: 12, weight: isCur ? .semibold : .medium))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isCur ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(isCur ? Color.white.opacity(0.38) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Reset / Default Preset button
                Button {
                    applyPreset(.userPersonalSky)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 2. Main Studio Split: Interactive Arc Color Pad on Left, Live Space Preview on Right
            HStack(alignment: .top, spacing: 20) {
                // LEFT: Arc SpaceStyleColorPad + Controls Card
                VStack(spacing: 14) {
                    // 2D Hue-Saturation Color Pad with draggable multi-stop handles
                    ArcColorPadWheel(
                        stops: effectiveStops,
                        activeStopIndex: $activeStopIndex,
                        intensity: currentTheme.intensityFactor,
                        onUpdateStop: { index, newColor in
                            updateStopColor(at: index, to: newColor)
                        }
                    )
                    .frame(height: 196)

                    // Control Bar directly under the Color Pad: [+] [-] color stops on left, Sun/Moon appearance on right
                    HStack(spacing: 8) {
                        // Add / Remove Gradient Color Stop Buttons (up to 3 stops)
                        HStack(spacing: 6) {
                            Button {
                                addGradientStop()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Add Color")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(effectiveStops.count < 3 ? 0.12 : 0.04))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(effectiveStops.count >= 3)
                            .opacity(effectiveStops.count < 3 ? 1.0 : 0.4)
                            .help("Add a blended gradient color to this space")

                            if effectiveStops.count > 1 {
                                Button {
                                    removeGradientStop()
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 24, height: 24)
                                        .background(
                                            Circle()
                                                .fill(Color.white.opacity(0.10))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Remove last color stop")
                            }

                            // Native Color Well for exact picking of active stop
                            ColorPicker("", selection: activeStopColorBinding, supportsOpacity: false)
                                .labelsHidden()
                                .scaleEffect(0.88)
                                .help("Pick exact color for selected stop")
                        }

                        Spacer()

                        // Arc Sun / Moon Light-Dark Appearance Pill
                        HStack(spacing: 2) {
                            appearanceModeButton(
                                icon: "sun.max.fill",
                                label: "Light",
                                isSelected: !currentTheme.prefersLightForeground
                            ) {
                                mutateCurrentTheme { $0.prefersLightForeground = false }
                            }

                            appearanceModeButton(
                                icon: "moon.fill",
                                label: "Dark",
                                isSelected: currentTheme.prefersLightForeground
                            ) {
                                mutateCurrentTheme { $0.prefersLightForeground = true }
                            }
                        }
                        .padding(3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.28))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                    }

                    // Arc Vibrancy / Intensity Slider + Tactile Grain Dial
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Text("Intensity")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)

                            ArcGradientTrackSlider(
                                value: Binding(
                                    get: { currentTheme.intensityFactor },
                                    set: { val in mutateCurrentTheme { $0.intensityFactor = val } }
                                ),
                                range: 0.06...1.0,
                                tintColors: [
                                    currentTheme.primaryColor.lightened(by: 0.65).swiftUIColor,
                                    currentTheme.primaryColor.swiftUIColor
                                ]
                            )
                            .frame(height: 20)

                            Text("\(Int(round(currentTheme.intensityFactor * 100)))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Text("Texture")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)

                            ArcGradientTrackSlider(
                                value: Binding(
                                    get: { currentTheme.grainIntensity },
                                    set: { val in mutateCurrentTheme { $0.grainIntensity = val } }
                                ),
                                range: 0.0...1.0,
                                tintColors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.55)
                                ]
                            )
                            .frame(height: 20)

                            Text("\(Int(round(currentTheme.grainIntensity * 100)))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .frame(maxWidth: .infinity)

                // RIGHT: Live Space Sidebar Preview Card
                liveMiniSidebarPreview
                    .frame(width: 230, height: 306)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.32), radius: 14, x: 0, y: 6)
            }

            // 3. Curated Arc Swatch Presets Strip (Full width, single clean horizontal row)
            VStack(alignment: .leading, spacing: 8) {
                Text("Presets")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(SpaceTheme.presets, id: \.name) { preset in
                        let isSelected = currentTheme.primaryColor.hexString == preset.theme.primaryColor.hexString
                            && currentTheme.prefersLightForeground == preset.theme.prefersLightForeground
                        Button {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                                applyPreset(preset.theme)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: preset.theme.renderedGradientColors,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Circle()
                                                .stroke(isSelected ? Color.white : Color.white.opacity(0.22), lineWidth: isSelected ? 2.2 : 1)
                                        )
                                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(preset.theme.foregroundColor)
                                    }
                                }

                                Text(preset.name)
                                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.09) : Color.white.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("\(preset.name) — \(preset.subtitle)")
                    }
                }
            }
        }
        .onAppear {
            if let activeIdx = browserState.spaces.firstIndex(where: { $0.id == browserState.activeSpaceID }) {
                selectedSpaceIndex = activeIdx
            }
        }
    }

    // MARK: - Appearance Mode Button

    @ViewBuilder
    private func appearanceModeButton(
        icon: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live Mini Sidebar Preview

    private var liveMiniSidebarPreview: some View {
        ZStack {
            LinearGradient(
                colors: currentTheme.renderedGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 9) {
                // Window Traffic Lights + Sidebar Icon
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 8, height: 8)
                    Circle().fill(Color(red: 0.15, green: 0.78, blue: 0.25)).frame(width: 8, height: 8)
                    Spacer()
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(currentTheme.secondaryForegroundColor)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Mock URL Bar Pill
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                    Text("alpbrowser.app")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.system(size: 8.5))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(currentTheme.pillBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(currentTheme.pillBorderColor, lineWidth: 0.7))
                .foregroundStyle(currentTheme.foregroundColor.opacity(0.9))
                .padding(.horizontal, 10)

                // Mock 2x2 Favorites Tiles
                HStack(spacing: 5) {
                    ForEach(["globe", "star.fill", "doc.text.fill", "terminal.fill"], id: \.self) { sym in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(currentTheme.pillBackground)
                            .frame(height: 24)
                            .overlay(
                                Image(systemName: sym)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(currentTheme.foregroundColor.opacity(0.85))
                            )
                    }
                }
                .padding(.horizontal, 10)

                // Space Title Header
                HStack(spacing: 5) {
                    Text(currentSpace.iconEmoji)
                        .font(.system(size: 11))
                    Text(currentSpace.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(currentTheme.foregroundColor)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)

                // Mock Selected Tab
                HStack(spacing: 6) {
                    Circle()
                        .fill(currentTheme.effectiveAccentColor)
                        .frame(width: 6, height: 6)
                    Text("Alp Browser — Clean Room")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "minus")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(currentTheme.secondaryForegroundColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(currentTheme.selectionBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(currentTheme.foregroundColor)
                .padding(.horizontal, 10)

                // Mock Inactive Tab
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                    Text("Research & Notes")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(currentTheme.secondaryForegroundColor)
                .padding(.horizontal, 10)

                Spacer()

                // Mock Bottom Bar matching Arc
                HStack {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10))
                    Spacer()
                    Text(currentSpace.iconEmoji)
                        .font(.system(size: 11))
                    Circle()
                        .fill(currentTheme.secondaryForegroundColor.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(currentTheme.secondaryForegroundColor)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Helpers & Mutators

    private var activeStopColorBinding: Binding<Color> {
        Binding<Color>(
            get: {
                let stops = effectiveStops
                let idx = min(max(activeStopIndex, 0), stops.count - 1)
                return stops[idx].swiftUIColor
            },
            set: { newCol in
                let rgba = RGBAColor(color: newCol)
                updateStopColor(at: activeStopIndex, to: rgba)
            }
        )
    }

    private func updateStopColor(at index: Int, to newColor: RGBAColor) {
        mutateCurrentTheme { th in
            var stops = th.colorStops.isEmpty ? [th.primaryColor] : th.colorStops
            let safeIdx = min(max(index, 0), stops.count - 1)
            stops[safeIdx] = newColor
            th.colorStops = stops
            th.primaryColor = stops[0]
            if stops.count >= 2 {
                th.secondaryColor = stops[1]
            } else {
                th.secondaryColor = stops[0].darkened(by: 0.32)
            }
            if stops.count >= 3 {
                th.accentColor = stops[2]
            } else {
                th.accentColor = stops[0].lightened(by: 0.32)
            }
        }
    }

    private func addGradientStop() {
        mutateCurrentTheme { th in
            var stops = th.colorStops.isEmpty ? [th.primaryColor] : th.colorStops
            guard stops.count < 3 else { return }
            let lastHsb = stops.last?.hsb ?? (hue: 0.55, saturation: 0.65, brightness: 0.85)
            let shiftedHue = fmod(lastHsb.hue + 0.14, 1.0)
            let nextColor = RGBAColor(
                hue: shiftedHue,
                saturation: max(0.45, lastHsb.saturation),
                brightness: max(0.65, lastHsb.brightness)
            )
            stops.append(nextColor)
            th.colorStops = stops
            if stops.count == 2 {
                th.secondaryColor = nextColor
            } else if stops.count == 3 {
                th.accentColor = nextColor
            }
            activeStopIndex = stops.count - 1
        }
    }

    private func removeGradientStop() {
        mutateCurrentTheme { th in
            var stops = th.colorStops.isEmpty ? [th.primaryColor] : th.colorStops
            guard stops.count > 1 else { return }
            stops.removeLast()
            th.colorStops = stops
            activeStopIndex = min(activeStopIndex, stops.count - 1)
        }
    }

    private func applyPreset(_ presetTheme: SpaceTheme) {
        mutateCurrentTheme { th in
            th = presetTheme
        }
        activeStopIndex = 0
    }

    private func mutateCurrentTheme(_ block: (inout SpaceTheme) -> Void) {
        let idx = min(max(selectedSpaceIndex, 0), max(0, browserState.spaces.count - 1))
        guard browserState.spaces.indices.contains(idx) else { return }
        block(&browserState.spaces[idx].theme)
        browserState.scheduleSave()
    }
}

// MARK: - Interactive 2D Hue-Saturation Color Pad (Arc SpaceStyleColorPadView)

struct ArcColorPadWheel: View {
    let stops: [RGBAColor]
    @Binding var activeStopIndex: Int
    let intensity: Double
    let onUpdateStop: (Int, RGBAColor) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Smooth 2D Hue (horizontal) x Saturation/Brightness (vertical) spectrum pad
                Canvas { context, canvasSize in
                    let cols = 64
                    let rows = 36
                    let cellW = canvasSize.width / CGFloat(cols)
                    let cellH = canvasSize.height / CGFloat(rows)

                    for r in 0..<rows {
                        let vNorm = Double(r) / Double(rows - 1)
                        let saturation = 0.20 + vNorm * 0.80
                        let brightness = 0.96 - vNorm * 0.34
                        for c in 0..<cols {
                            let hue = Double(c) / Double(cols)
                            let col = Color(hue: hue, saturation: saturation, brightness: brightness)
                            let rect = CGRect(
                                x: CGFloat(c) * cellW,
                                y: CGFloat(r) * cellH,
                                width: cellW + 0.8,
                                height: cellH + 0.8
                            )
                            context.fill(Path(rect), with: .color(col))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let xNorm = min(max(Double(value.location.x / max(1, size.width)), 0), 1)
                            let yNorm = min(max(Double(value.location.y / max(1, size.height)), 0), 1)
                            let saturation = 0.20 + yNorm * 0.80
                            let brightness = 0.96 - yNorm * 0.34
                            let picked = RGBAColor(hue: xNorm, saturation: saturation, brightness: brightness)
                            onUpdateStop(activeStopIndex, picked)
                        }
                )

                // Draggable Color Nodes for each stop (1, 2, or 3 stops)
                ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                    let pos = position(for: stop, in: size)
                    let isSelected = (idx == activeStopIndex)

                    ZStack {
                        Circle()
                            .fill(stop.swiftUIColor)
                            .frame(width: isSelected ? 28 : 22, height: isSelected ? 28 : 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: isSelected ? 3.0 : 2.0)
                            )
                            .shadow(color: .black.opacity(0.45), radius: 5, y: 2)

                        if stops.count > 1 {
                            Text("\(idx + 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(stop.luminance > 0.55 ? Color.black.opacity(0.8) : Color.white)
                        }
                    }
                    .position(pos)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                activeStopIndex = idx
                                let xNorm = min(max(Double(value.location.x / max(1, size.width)), 0), 1)
                                let yNorm = min(max(Double(value.location.y / max(1, size.height)), 0), 1)
                                let saturation = 0.20 + yNorm * 0.80
                                let brightness = 0.96 - yNorm * 0.34
                                let picked = RGBAColor(hue: xNorm, saturation: saturation, brightness: brightness)
                                onUpdateStop(idx, picked)
                            }
                    )
                    .onTapGesture {
                        activeStopIndex = idx
                    }
                }
            }
        }
    }

    private func position(for color: RGBAColor, in size: CGSize) -> CGPoint {
        let hsb = color.hsb
        let x = CGFloat(min(max(hsb.hue, 0.03), 0.97)) * size.width
        let sNorm = min(max((hsb.saturation - 0.20) / 0.80, 0.06), 0.94)
        let y = CGFloat(sNorm) * size.height
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Custom Gradient Track Slider

struct ArcGradientTrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tintColors: [Color]

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: tintColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                    )

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: clampedProgress * (width - 16))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let norm = min(max(Double(drag.location.x / width), 0), 1)
                        value = range.lowerBound + norm * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}
