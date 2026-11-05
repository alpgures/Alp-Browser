import SwiftUI
import WebKit
import AppKit

// MARK: - 1. Arc Peek Floating Modal Card

public struct PeekOverlayView: View {
    @EnvironmentObject var browserState: BrowserState
    public let session: PeekSession

    @State private var peekTab: TabItem

    public init(session: PeekSession) {
        self.session = session
        _peekTab = State(initialValue: TabItem(title: session.title, urlString: session.urlString))
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    closePeek()
                }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(browserState.activeTheme.effectiveAccentColor)

                        Text("Arc Peek")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))

                        Text("•")
                            .foregroundStyle(.white.opacity(0.35))

                        Text(peekTab.urlString)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button {
                        let tab = browserState.openNewTab(urlString: peekTab.urlString, title: peekTab.title, inBackground: true)
                        browserState.addSplitPane(withTabID: tab.id)
                        closePeek()
                    } label: {
                        Label("Split View", systemImage: "rectangle.split.2x1")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        browserState.expandPeekToFullTab()
                    } label: {
                        Label("Expand to Full Tab", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(browserState.activeTheme.primaryColor.swiftUIColor)
                    .controlSize(.small)

                    Button {
                        closePeek()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Close Peek (Esc)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.10, green: 0.10, blue: 0.13))

                WebViewRepresentable(tab: peekTab)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(6)
            }
            .frame(maxWidth: 960, maxHeight: 680)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 36, y: 16)
            .padding(36)
        }
        .onDisappear {
            WebViewPool.shared.destroyWebView(for: peekTab.id)
        }
    }

    private func closePeek() {
        WebViewPool.shared.destroyWebView(for: peekTab.id)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            browserState.peekSession = nil
        }
    }
}

// MARK: - 2. Arc Max: Find & Ask on Page Bar (⌘F)

public struct FindAndAskBarView: View {
    @EnvironmentObject var browserState: BrowserState
    @FocusState private var isFocused: Bool

    @State private var query: String = ""
    @State private var aiAnswer: String = ""
    @State private var isAskingAI: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(browserState.activeTheme.primaryColor.swiftUIColor)

                TextField("Find text or Ask Arc Max about this page...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit {
                        if query.contains("?") || query.split(separator: " ").count >= 3 {
                            askArcMaxAI()
                        } else if let tabID = browserState.activeTabID {
                            WebViewPool.shared.findOnPage(query: query, forward: true, in: tabID)
                        }
                    }
                    .onChange(of: query) { _, newValue in
                        if !newValue.isEmpty, newValue.split(separator: " ").count <= 2, let tabID = browserState.activeTabID {
                            WebViewPool.shared.findOnPage(query: newValue, forward: true, in: tabID)
                        }
                    }

                Button {
                    if let tabID = browserState.activeTabID {
                        WebViewPool.shared.findOnPage(query: query, forward: false, in: tabID)
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Previous Match")

                Button {
                    if let tabID = browserState.activeTabID {
                        WebViewPool.shared.findOnPage(query: query, forward: true, in: tabID)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Next Match")

                Button {
                    askArcMaxAI()
                } label: {
                    HStack(spacing: 4) {
                        if isAskingAI {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11))
                        }
                        Text(query.isEmpty ? "5s Summary" : "Ask AI")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(browserState.activeTheme.primaryColor.swiftUIColor))
                }
                .buttonStyle(.plain)
                .disabled(isAskingAI)

                Button {
                    browserState.isFindAndAskBarPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }

            if !aiAnswer.isEmpty {
                Divider().overlay(Color.white.opacity(0.14))

                ScrollView {
                    Text(aiAnswer)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 210)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.12).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        )
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }

    private func askArcMaxAI() {
        guard let tabID = browserState.activeTabID else { return }
        let promptQuestion = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Give me a 5-second bulleted summary of the key takeaways on this page."
            : query

        isAskingAI = true
        Task {
            let extracted = await WebViewPool.shared.extractPageText(in: tabID)
            let answer = await OCISyncService.shared.askArcMax(
                question: promptQuestion,
                pageTitle: extracted.title,
                pageURL: extracted.url,
                pageText: extracted.content,
                sshAlias: browserState.ociConfig.sshHostAlias
            )
            await MainActor.run {
                self.aiAnswer = answer
                self.isAskingAI = false
            }
        }
    }
}

// MARK: - 3. Authentic Arc Interactive Color Wheel & Theme Studio

public struct SpaceThemePickerView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var selectedDotIndex: Int = 0
    @State private var hexInput: String = "#6CBAD9"
    @State private var dotBrightness: Double = 0.85

    private var theme: SpaceTheme {
        browserState.activeSpace.theme
    }

    private var stops: [RGBAColor] {
        theme.colorStops.isEmpty ? [theme.primaryColor] : theme.colorStops
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Header with Space Name & Close Button
            HStack(spacing: 8) {
                Text(browserState.activeSpace.iconEmoji)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(browserState.activeSpace.title) Theme")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("\(stops.first?.hexString ?? "#6CBAD9") • \(theme.prefersLightForeground ? "Dark Mode" : "Light Frosted")")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Add / Remove Gradient Dots (+ / -) just like Arc's wheel controls
                HStack(spacing: 4) {
                    Button {
                        removeColorDot()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(stops.count <= 1)
                    .opacity(stops.count <= 1 ? 0.35 : 1.0)
                    .help("Remove Gradient Color Dot")

                    Text("\(stops.count) dot\(stops.count > 1 ? "s" : "")")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 38)

                    Button {
                        addColorDot()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(stops.count >= 3)
                    .opacity(stops.count >= 3 ? 0.35 : 1.0)
                    .help("Add Gradient Color Dot (Up to 3)")
                }

                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        browserState.isThemePickerPresented = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 2. Interactive 2D Frosted Arc Color Wheel + Vertical Intensity Feel Bar
            HStack(spacing: 16) {
                ArcInteractiveColorWheel(
                    stops: Binding(
                        get: { stops },
                        set: { newStops in
                            updateThemeStops(newStops)
                        }
                    ),
                    selectedDotIndex: $selectedDotIndex,
                    onSelectOrDrag: { idx in
                        if stops.indices.contains(idx) {
                            hexInput = stops[idx].hexString
                            dotBrightness = stops[idx].hsb.brightness
                        }
                    }
                )
                .frame(width: 188, height: 188)

                // Right Column: Vertical Intensity & Grain Controls (Arc's tactile sliders)
                VStack(alignment: .leading, spacing: 12) {
                    // Light vs Dark Appearance Pill Switcher
                    VStack(alignment: .leading, spacing: 5) {
                        Text("APPEARANCE")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Button {
                                browserState.activeSpace.theme.prefersLightForeground = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "sun.max.fill")
                                        .font(.system(size: 10))
                                    Text("Light")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(!theme.prefersLightForeground ? Color.primary.opacity(0.16) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                browserState.activeSpace.theme.prefersLightForeground = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "moon.stars.fill")
                                        .font(.system(size: 10))
                                    Text("Dark")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(theme.prefersLightForeground ? Color.primary.opacity(0.16) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(2)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
                    }

                    // Brightness of Active Dot
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Brightness")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(dotBrightness * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $dotBrightness, in: 0.15...1.0)
                            .controlSize(.small)
                            .onChange(of: dotBrightness) { _, newB in
                                guard stops.indices.contains(selectedDotIndex) else { return }
                                var currentStops = stops
                                let hsb = currentStops[selectedDotIndex].hsb
                                currentStops[selectedDotIndex] = RGBAColor(
                                    hue: hsb.hue,
                                    saturation: hsb.saturation,
                                    brightness: newB
                                )
                                hexInput = currentStops[selectedDotIndex].hexString
                                updateThemeStops(currentStops)
                            }
                    }

                    // Pigment Intensity (Arc's `intensityFactor`)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Tint Intensity")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(theme.intensityFactor * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $browserState.activeSpace.theme.intensityFactor, in: 0.08...1.0)
                            .controlSize(.small)
                    }

                    // Film Grain (`noiseFactor`)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Analog Grain")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(theme.grainIntensity * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $browserState.activeSpace.theme.grainIntensity, in: 0.0...1.0)
                            .controlSize(.small)
                    }
                }
                .frame(width: 145)
            }

            // 3. Hex Code Input + Eyedropper Row
            HStack(spacing: 8) {
                Text("Hex Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("#6CBAD9", text: $hexInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .frame(width: 92)
                    .onSubmit {
                        applyHexInput()
                    }

                Button("Apply") {
                    applyHexInput()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Toggle("Vibrancy", isOn: $browserState.activeSpace.theme.isVibrant)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Divider()

            // 4. Your Exact Saved Arc Config Themes & Curated Swatches
            VStack(alignment: .leading, spacing: 7) {
                Text("YOUR ARC CONFIG & PRESETS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SpaceTheme.presets, id: \.name) { preset in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    browserState.activeSpace.theme = preset.theme
                                    selectedDotIndex = 0
                                    if let first = preset.theme.colorStops.first {
                                        hexInput = first.hexString
                                        dotBrightness = first.hsb.brightness
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: preset.theme.renderedGradientColors,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(preset.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text(preset.subtitle)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 5. Official Arc.app ColorPicker Swatches (loaded directly from ARC_SpaceStyleEditor.bundle)
                let arcSwatches = ArcAssetLoader.shared.arcOfficialColorSwatches
                if !arcSwatches.isEmpty {
                    Text("OFFICIAL ARC.APP SWATCHES")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(arcSwatches, id: \.group) { group in
                                ForEach(Array(group.colors.enumerated()), id: \.offset) { _, swatch in
                                    Button {
                                        var current = stops
                                        let idx = min(selectedDotIndex, max(0, current.count - 1))
                                        if current.indices.contains(idx) {
                                            current[idx] = swatch
                                            hexInput = swatch.hexString
                                            dotBrightness = swatch.hsb.brightness
                                            updateThemeStops(current)
                                        }
                                    } label: {
                                        Circle()
                                            .fill(swatch.swiftUIColor)
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help("\(group.group) (\(swatch.hexString))")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 382)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 28, y: 12)
        .onAppear {
            selectedDotIndex = 0
            if let first = stops.first {
                hexInput = first.hexString
                dotBrightness = first.hsb.brightness
            }
        }
    }

    private func updateThemeStops(_ newStops: [RGBAColor]) {
        guard let first = newStops.first else { return }
        browserState.activeSpace.theme.colorStops = newStops
        browserState.activeSpace.theme.primaryColor = first
        if newStops.count >= 2 {
            browserState.activeSpace.theme.secondaryColor = newStops[1]
        } else {
            browserState.activeSpace.theme.secondaryColor = first.darkened(by: 0.35)
        }
        if newStops.count >= 3 {
            browserState.activeSpace.theme.accentColor = newStops[2]
        } else {
            browserState.activeSpace.theme.accentColor = first.lightened(by: 0.35)
        }
    }

    private func addColorDot() {
        var current = stops
        guard current.count < 3 else { return }
        let baseHSB = current.last?.hsb ?? (hue: 0.55, saturation: 0.5, brightness: 0.85)
        let shiftedHue = (baseHSB.hue + 0.14).truncatingRemainder(dividingBy: 1.0)
        let newColor = RGBAColor(hue: shiftedHue, saturation: max(0.45, baseHSB.saturation), brightness: baseHSB.brightness)
        current.append(newColor)
        selectedDotIndex = current.count - 1
        hexInput = newColor.hexString
        dotBrightness = newColor.hsb.brightness
        updateThemeStops(current)
    }

    private func removeColorDot() {
        var current = stops
        guard current.count > 1 else { return }
        current.removeLast()
        selectedDotIndex = min(selectedDotIndex, current.count - 1)
        hexInput = current[selectedDotIndex].hexString
        dotBrightness = current[selectedDotIndex].hsb.brightness
        updateThemeStops(current)
    }

    private func applyHexInput() {
        guard let parsed = RGBAColor(hex: hexInput) else { return }
        var current = stops
        let idx = min(selectedDotIndex, current.count - 1)
        current[idx] = parsed
        dotBrightness = parsed.hsb.brightness
        hexInput = parsed.hexString
        updateThemeStops(current)
    }
}

// MARK: - Interactive 2D Frosted Arc Color Wheel Component

struct ArcInteractiveColorWheel: View {
    @Binding var stops: [RGBAColor]
    @Binding var selectedDotIndex: Int
    var onSelectOrDrag: (Int) -> Void

    private let spectrumColors: [Color] = stride(from: 0.0, through: 1.0, by: 0.05).map {
        Color(hue: $0, saturation: 0.88, brightness: 0.96)
    }

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2.0
            let center = CGPoint(x: geo.size.width / 2.0, y: geo.size.height / 2.0)

            ZStack {
                // 1. Frosted Angular Hue Spectrum + Radial Saturation Desaturation toward Center
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: spectrumColors),
                            center: .center
                        )
                    )
                    .overlay(
                        RadialGradient(
                            colors: [
                                Color.white,
                                Color.white.opacity(0.35),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                    .blur(radius: 6)
                    .overlay {
                        if let dotGrid = ArcAssetLoader.shared.spaceStyleImage(named: "DotGrid") {
                            Image(nsImage: dotGrid)
                                .resizable(resizingMode: .tile)
                                .opacity(0.32)
                                .blendMode(.overlay)
                        }
                    }
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

                // 2. Connecting Polyline between Multi-Stop Gradient Dots
                if stops.count > 1 {
                    Path { path in
                        for (idx, stop) in stops.enumerated() {
                            let pt = pointForColor(stop, center: center, radius: radius - 14)
                            if idx == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
                }

                // 3. Draggable Color Dots (1 to 3)
                ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                    let pt = pointForColor(stop, center: center, radius: radius - 14)
                    let isSelected = idx == selectedDotIndex

                    ZStack {
                        Circle()
                            .fill(stop.swiftUIColor)
                            .frame(width: isSelected ? 28 : 22, height: isSelected ? 28 : 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: isSelected ? 3.0 : 2.0)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 5, y: 2)

                        if stops.count > 1 {
                            Text("\(idx + 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(stop.luminance > 0.6 ? .black : .white)
                        }
                    }
                    .position(pt)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectedDotIndex = idx
                                let updated = colorForPoint(
                                    value.location,
                                    center: center,
                                    maxRadius: radius - 14,
                                    preservingBrightness: stop.hsb.brightness
                                )
                                var next = stops
                                if next.indices.contains(idx) {
                                    next[idx] = updated
                                    stops = next
                                    onSelectOrDrag(idx)
                                }
                            }
                    )
                }
            }
            // Also allow clicking anywhere on the wheel to move the active dot immediately
            .contentShape(Circle())
            .onTapGesture { location in
                let idx = min(selectedDotIndex, max(0, stops.count - 1))
                guard stops.indices.contains(idx) else { return }
                let updated = colorForPoint(
                    location,
                    center: center,
                    maxRadius: radius - 14,
                    preservingBrightness: stops[idx].hsb.brightness
                )
                var next = stops
                next[idx] = updated
                stops = next
                onSelectOrDrag(idx)
            }
        }
    }

    private func pointForColor(_ color: RGBAColor, center: CGPoint, radius: CGFloat) -> CGPoint {
        let hsb = color.hsb
        let angle = hsb.hue * 2.0 * .pi
        let dist = CGFloat(min(max(hsb.saturation, 0), 1)) * radius
        return CGPoint(
            x: center.x + cos(angle) * dist,
            y: center.y + sin(angle) * dist
        )
    }

    private func colorForPoint(
        _ point: CGPoint,
        center: CGPoint,
        maxRadius: CGFloat,
        preservingBrightness brightness: Double
    ) -> RGBAColor {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx)
        if angle < 0 {
            angle += 2.0 * .pi
        }
        let hue = Double(angle / (2.0 * .pi))
        let distance = hypot(dx, dy)
        let saturation = Double(min(distance / maxRadius, 1.0))
        return RGBAColor(hue: hue, saturation: saturation, brightness: max(brightness, 0.25))
    }
}

// MARK: - 4. Arc Boosts 2.0 Studio Popover

public struct BoostStudioView: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject var webViewPool = WebViewPool.shared

    @State private var draftBoost: ArcBoost = ArcBoost(domain: "example.com")

    private var currentDomain: String {
        browserState.activeTab?.simplifiedDomain ?? "global"
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Arc Boost Studio • \(currentDomain)", systemImage: "bolt.fill")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("", isOn: $draftBoost.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: draftBoost.isEnabled) { _, _ in
                        browserState.upsertBoost(draftBoost)
                    }

                Button {
                    browserState.isBoostStudioPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                if let tabID = browserState.activeTabID {
                    webViewPool.setElementZapperActive(true, for: tabID)
                    browserState.isBoostStudioPresented = false
                }
            } label: {
                HStack {
                    Image(systemName: "wand.and.rays")
                    Text("Zap Page Element (Click to Hide Elements)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.purple.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.purple.opacity(0.55), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Group {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hue Shift")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int(draftBoost.hueRotateDegrees))°")
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    Slider(value: $draftBoost.hueRotateDegrees, in: -180...180)
                        .onChange(of: draftBoost.hueRotateDegrees) { _, _ in
                            browserState.upsertBoost(draftBoost)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Page Zoom")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int(draftBoost.fontScalePercent))%")
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    Slider(value: $draftBoost.fontScalePercent, in: 75...150)
                        .onChange(of: draftBoost.fontScalePercent) { _, _ in
                            browserState.upsertBoost(draftBoost)
                        }
                }

                Toggle("Smart Dark Mode Invert", isOn: $draftBoost.invertColors)
                    .font(.system(size: 12))
                    .onChange(of: draftBoost.invertColors) { _, _ in
                        browserState.upsertBoost(draftBoost)
                    }
            }

            if !draftBoost.zappedSelectors.isEmpty {
                HStack {
                    Text("\(draftBoost.zappedSelectors.count) zapped elements hidden")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Zapped") {
                        draftBoost.zappedSelectors.removeAll()
                        browserState.upsertBoost(draftBoost)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.purple)
                }
            }

            Divider()

            Text("Custom CSS for \(currentDomain)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $draftBoost.customCSS)
                .font(.system(size: 11.5, design: .monospaced))
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: draftBoost.customCSS) { _, _ in
                    browserState.upsertBoost(draftBoost)
                }
        }
        .padding(16)
        .frame(width: 350)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .onAppear {
            if let existing = browserState.boost(forDomain: currentDomain) {
                draftBoost = existing
            } else {
                draftBoost = ArcBoost(domain: currentDomain, name: "\(currentDomain) Boost")
            }
        }
    }
}
