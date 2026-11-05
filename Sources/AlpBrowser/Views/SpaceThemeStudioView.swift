//
//  SpaceThemeStudioView.swift
//  Alp Browser
//
//  Space theme studio: pick a space, shape its gradient (up to three colour
//  stops on a hue/tone field), choose a light or dark foreground, tune
//  intensity and texture, or start from a preset. A small live preview
//  shows the result. All controls in this file are original Alp code.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Studio

public struct SpaceThemeStudioView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var spaceIndex: Int = 0
    @State private var stopIndex: Int = 0

    private let maxStops = 3

    public init() {}

    // MARK: Derived state

    private var space: AlpSpace {
        browserState.spaces.indices.contains(spaceIndex) ? browserState.spaces[spaceIndex] : browserState.activeSpace
    }

    private var theme: SpaceTheme { space.theme }

    private var stops: [RGBAColor] {
        theme.colorStops.isEmpty ? [theme.primaryColor] : theme.colorStops
    }

    private var safeStopIndex: Int { min(max(stopIndex, 0), stops.count - 1) }

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            spaceBar

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 14) {
                    ThemeColorField(
                        stops: stops,
                        selected: Binding(get: { safeStopIndex }, set: { stopIndex = $0 }),
                        onPick: { index, color in setStop(index, to: color) }
                    )
                    .frame(height: 196)

                    stopControls
                    tuningCard
                }
                .frame(maxWidth: .infinity)

                StudioMiniPreview(space: space)
                    .frame(width: 230, height: 306)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.32), radius: 14, x: 0, y: 6)
            }

            presetRow
        }
        .onAppear {
            if let idx = browserState.spaces.firstIndex(where: { $0.id == browserState.activeSpaceID }) {
                spaceIndex = idx
            }
        }
    }

    // MARK: Sections

    private var spaceBar: some View {
        HStack(spacing: 10) {
            Text("Space")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(Array(browserState.spaces.enumerated()), id: \.element.id) { idx, sp in
                    let isCurrent = idx == spaceIndex
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            spaceIndex = idx
                            stopIndex = 0
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(sp.iconEmoji).font(.system(size: 13))
                            Text(sp.title).font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(isCurrent ? 0.16 : 0.05)))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(isCurrent ? 0.38 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button {
                apply(.userPersonalSky)
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var stopControls: some View {
        HStack(spacing: 8) {
            Button(action: addStop) {
                Label("Add Color", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(stops.count >= maxStops)
            .opacity(stops.count < maxStops ? 1 : 0.4)
            .help("Add a blended gradient color to this space")

            if stops.count > 1 {
                Button(action: removeStop) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("Remove the last color")
            }

            ColorPicker("", selection: selectedStopBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Pick an exact color for the selected stop")

            Spacer()

            Picker("Appearance", selection: foregroundBinding) {
                Label("Light", systemImage: "sun.max.fill").tag(false)
                Label("Dark", systemImage: "moon.fill").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
    }

    private var tuningCard: some View {
        VStack(spacing: 10) {
            tuningRow(
                symbol: "circle.lefthalf.filled",
                title: "Intensity",
                value: Binding(get: { theme.intensityFactor }, set: { v in edit { $0.intensityFactor = v } }),
                range: 0.06...1.0,
                track: [theme.primaryColor.lightened(by: 0.65).swiftUIColor, theme.primaryColor.swiftUIColor]
            )
            tuningRow(
                symbol: "sparkles",
                title: "Texture",
                value: Binding(get: { theme.grainIntensity }, set: { v in edit { $0.grainIntensity = v } }),
                range: 0...1,
                track: [Color.white.opacity(0.18), Color.white.opacity(0.55)]
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func tuningRow(symbol: String, title: String, value: Binding<Double>, range: ClosedRange<Double>, track: [Color]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            ThemeValueSlider(value: value, range: range, track: track, label: title)
                .frame(height: 20)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(SpaceTheme.presets, id: \.name) { preset in
                    let isSelected = theme.primaryColor.hexString == preset.theme.primaryColor.hexString
                        && theme.prefersLightForeground == preset.theme.prefersLightForeground
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { apply(preset.theme) }
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(LinearGradient(colors: preset.theme.renderedGradientColors,
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(Color.white.opacity(isSelected ? 1 : 0.22), lineWidth: isSelected ? 2.2 : 1))
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(preset.theme.foregroundColor)
                                    }
                                }
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            Text(preset.name)
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(isSelected ? 0.09 : 0.03)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("\(preset.name) — \(preset.subtitle)")
                }
            }
        }
    }

    // MARK: Bindings and edits

    private var selectedStopBinding: Binding<Color> {
        Binding(
            get: { stops[safeStopIndex].swiftUIColor },
            set: { setStop(safeStopIndex, to: RGBAColor(color: $0)) }
        )
    }

    private var foregroundBinding: Binding<Bool> {
        Binding(
            get: { theme.prefersLightForeground },
            set: { v in edit { $0.prefersLightForeground = v } }
        )
    }

    private func edit(_ block: (inout SpaceTheme) -> Void) {
        guard browserState.spaces.indices.contains(spaceIndex) else { return }
        block(&browserState.spaces[spaceIndex].theme)
        browserState.scheduleSave()
    }

    /// Keeps primary/secondary/accent in step with the first three gradient stops.
    private func setStop(_ index: Int, to color: RGBAColor) {
        edit { th in
            var list = th.colorStops.isEmpty ? [th.primaryColor] : th.colorStops
            list[min(max(index, 0), list.count - 1)] = color
            th.colorStops = list
            th.primaryColor = list[0]
            th.secondaryColor = list.count >= 2 ? list[1] : list[0].darkened(by: 0.32)
            th.accentColor = list.count >= 3 ? list[2] : list[0].lightened(by: 0.32)
        }
    }

    private func addStop() {
        guard stops.count < maxStops else { return }
        let last = stops.last?.hsb ?? (hue: 0.55, saturation: 0.65, brightness: 0.85)
        let next = RGBAColor(
            hue: fmod(last.hue + 0.14, 1.0),
            saturation: max(0.45, last.saturation),
            brightness: max(0.65, last.brightness)
        )
        edit { th in
            var list = th.colorStops.isEmpty ? [th.primaryColor] : th.colorStops
            list.append(next)
            th.colorStops = list
            if list.count == 2 { th.secondaryColor = next } else { th.accentColor = next }
        }
        stopIndex = stops.count - 1
    }

    private func removeStop() {
        guard stops.count > 1 else { return }
        edit { th in
            var list = th.colorStops.isEmpty ? [th.primaryColor] : th.colorStops
            list.removeLast()
            th.colorStops = list
        }
        stopIndex = min(stopIndex, stops.count - 1)
    }

    private func apply(_ preset: SpaceTheme) {
        edit { $0 = preset }
        stopIndex = 0
    }
}

// MARK: - Hue / tone colour field

/// A rectangular field: hue runs left to right, tone (saturation and brightness together)
/// runs top to bottom. Each gradient stop is a handle; dragging near a handle moves it,
/// dragging elsewhere moves the selected one.
struct ThemeColorField: View {
    let stops: [RGBAColor]
    @Binding var selected: Int
    let onPick: (Int, RGBAColor) -> Void

    private let grabRadius: CGFloat = 20
    private let rowCount = 28

    /// Shared mapping between vertical position (0 top … 1 bottom) and tone.
    private static func tone(at y: Double) -> (saturation: Double, brightness: Double) {
        (0.20 + 0.80 * y, 0.96 - 0.34 * y)
    }

    private static func normalizedY(forSaturation s: Double) -> Double {
        min(max((s - 0.20) / 0.80, 0.06), 0.94)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                field
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1))

                ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                    handle(for: stop, index: idx)
                        .position(point(for: stop, in: size))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let target = handleIndex(near: drag.startLocation, in: size) ?? selected
                        if target != selected { selected = target }
                        onPick(target, color(at: drag.location, in: size))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Color field")
    }

    /// Horizontal hue gradients stacked into rows; one gradient fill per row.
    private var field: some View {
        Canvas { context, canvasSize in
            let hues = stride(from: 0.0, through: 1.0, by: 1.0 / 12.0).map { $0 }
            let rowHeight = canvasSize.height / CGFloat(rowCount)
            for row in 0..<rowCount {
                let y = Double(row) / Double(rowCount - 1)
                let t = Self.tone(at: y)
                let gradient = Gradient(colors: hues.map {
                    Color(hue: min($0, 0.999), saturation: t.saturation, brightness: t.brightness)
                })
                let rect = CGRect(x: 0, y: CGFloat(row) * rowHeight, width: canvasSize.width, height: rowHeight + 0.8)
                context.fill(
                    Path(rect),
                    with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: canvasSize.width, y: 0))
                )
            }
        }
    }

    private func handle(for stop: RGBAColor, index: Int) -> some View {
        let isSelected = index == selected
        let diameter: CGFloat = isSelected ? 28 : 22
        return ZStack {
            Circle()
                .fill(stop.swiftUIColor)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(Color.white, lineWidth: isSelected ? 3 : 2))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
            if stops.count > 1 {
                Text("\(index + 1)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(stop.luminance > 0.55 ? Color.black.opacity(0.8) : Color.white)
            }
        }
    }

    private func color(at location: CGPoint, in size: CGSize) -> RGBAColor {
        let x = min(max(Double(location.x / max(1, size.width)), 0), 1)
        let y = min(max(Double(location.y / max(1, size.height)), 0), 1)
        let t = Self.tone(at: y)
        return RGBAColor(hue: x, saturation: t.saturation, brightness: t.brightness)
    }

    private func point(for color: RGBAColor, in size: CGSize) -> CGPoint {
        let hsb = color.hsb
        return CGPoint(
            x: CGFloat(min(max(hsb.hue, 0.03), 0.97)) * size.width,
            y: CGFloat(Self.normalizedY(forSaturation: hsb.saturation)) * size.height
        )
    }

    private func handleIndex(near location: CGPoint, in size: CGSize) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (idx, stop) in stops.enumerated() {
            let p = point(for: stop, in: size)
            let d = hypot(p.x - location.x, p.y - location.y)
            if d <= grabRadius, d < (best?.distance ?? .infinity) { best = (idx, d) }
        }
        return best?.index
    }
}

// MARK: - Value slider

/// A horizontal slider whose track is a gradient and whose thumb is a plain circle.
struct ThemeValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let track: [Color]
    let label: String

    private let thumb: CGFloat = 16

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumb)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: track, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                    .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.7))
                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: CGFloat(fraction) * usable)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let f = min(max(Double((drag.location.x - thumb / 2) / usable), 0), 1)
                        value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) * 0.05
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

// MARK: - Live preview

/// A miniature sidebar drawn with the space's current theme.
struct StudioMiniPreview: View {
    let space: AlpSpace

    private var theme: SpaceTheme { space.theme }

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.renderedGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 9) {
                windowChrome
                addressPill
                shortcutTiles
                spaceTitle
                selectedRow
                plainRow
                Spacer()
                footer
            }
        }
    }

    private var windowChrome: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 8, height: 8)
            Circle().fill(Color(red: 0.15, green: 0.78, blue: 0.25)).frame(width: 8, height: 8)
            Spacer()
            Image(systemName: "sidebar.left")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(theme.secondaryForegroundColor)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var addressPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill").font(.system(size: 8))
            Text("alpbrowser.app").font(.system(size: 10, weight: .medium))
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 8.5))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(theme.pillBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(theme.pillBorderColor, lineWidth: 0.7))
        .foregroundStyle(theme.foregroundColor.opacity(0.9))
        .padding(.horizontal, 10)
    }

    private var shortcutTiles: some View {
        HStack(spacing: 5) {
            ForEach(["globe", "star.fill", "doc.text.fill", "terminal.fill"], id: \.self) { symbol in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.pillBackground)
                    .frame(height: 24)
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.foregroundColor.opacity(0.85))
                    )
            }
        }
        .padding(.horizontal, 10)
    }

    private var spaceTitle: some View {
        HStack(spacing: 5) {
            Text(space.iconEmoji).font(.system(size: 11))
            Text(space.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.foregroundColor)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    private var selectedRow: some View {
        HStack(spacing: 6) {
            Circle().fill(theme.effectiveAccentColor).frame(width: 6, height: 6)
            Text("Welcome to Alp")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(theme.secondaryForegroundColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.selectionBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .foregroundStyle(theme.foregroundColor)
        .padding(.horizontal, 10)
    }

    private var plainRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 9))
            Text("Research & Notes").font(.system(size: 10, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(theme.secondaryForegroundColor)
        .padding(.horizontal, 10)
    }

    private var footer: some View {
        HStack {
            Image(systemName: "archivebox").font(.system(size: 10))
            Spacer()
            Text(space.iconEmoji).font(.system(size: 11))
            Spacer()
            Image(systemName: "plus").font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(theme.secondaryForegroundColor)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
