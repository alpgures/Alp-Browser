//
//  StartPageView.swift
//  Alp Browser
//
//  Native start page for new / blank tabs: live clock, time-aware greeting and a
//  per-day "main goal" note, over an offline layered backdrop (theme gradient,
//  mountain glyph watermark, ridge silhouettes, grain). No network, no image assets.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Per-day goal persistence

/// Keeps one goal note for the current calendar day in UserDefaults; a new day starts empty.
enum StartPageGoalStore {
    private static let dayKey = "alp.startPage.goalDay"
    private static let textKey = "alp.startPage.goalText"

    private static func dayStamp(_ date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    static func load() -> String {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == dayStamp() else { return "" }
        return defaults.string(forKey: textKey) ?? ""
    }

    static func save(_ text: String) {
        let defaults = UserDefaults.standard
        defaults.set(dayStamp(), forKey: dayKey)
        defaults.set(text, forKey: textKey)
    }
}

// MARK: - Start Page

struct StartPageView: View {
    @EnvironmentObject var browserState: BrowserState

    @State private var goal: String = StartPageGoalStore.load()
    @FocusState private var goalFocused: Bool

    private var theme: SpaceTheme { browserState.activeTheme }

    var body: some View {
        ZStack {
            StartPageBackdrop(theme: theme)
                .contentShape(Rectangle())
                .onTapGesture { goalFocused = false }

            GeometryReader { geo in
                let clockSize = min(104, max(48, geo.size.width * 0.16))
                VStack(spacing: 10) {
                    TimelineView(.everyMinute) { context in
                        VStack(spacing: 6) {
                            Text(context.date.formatted(.dateTime.hour().minute()))
                                .font(.system(size: clockSize, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(theme.foregroundColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)

                            Text(Self.greetingText(for: context.date))
                                .font(.system(size: max(18, clockSize * 0.30), weight: .medium, design: .rounded))
                                .foregroundStyle(theme.foregroundColor.opacity(0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }

                    TextField(
                        "Main goal",
                        text: $goal,
                        prompt: Text("What is your main goal for today?")
                            .foregroundStyle(theme.secondaryForegroundColor)
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(theme.foregroundColor)
                    .multilineTextAlignment(.center)
                    .focused($goalFocused)
                    .frame(maxWidth: 460)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(theme.secondaryForegroundColor.opacity(goalFocused ? 0.9 : 0.55))
                            .frame(height: 1)
                    }
                    .onSubmit { goalFocused = false }
                    .onChange(of: goal) { _, newValue in
                        StartPageGoalStore.save(newValue)
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .frame(width: geo.size.width, height: geo.size.height)
                // Optical centre sits a little above the geometric centre.
                .offset(y: -geo.size.height * 0.06)
            }

            VStack {
                Spacer()
                HStack {
                    TimelineView(.everyMinute) { context in
                        Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.secondaryForegroundColor)
                    }
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.bottom, 16)
            }
            .allowsHitTesting(false)
        }
        .clipped()
    }

    private static func greetingText(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let salutation: String
        switch hour {
        case 5..<12: salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        default: salutation = "Good evening"
        }
        let first = NSFullUserName()
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
        return first.isEmpty ? "\(salutation)." : "\(salutation), \(first)."
    }
}

// MARK: - Backdrop

/// Theme gradient, soft glow, mountain glyph watermark, ridge silhouettes and grain.
/// Stateless, so the per-minute clock refresh never redraws it.
private struct StartPageBackdrop: View {
    let theme: SpaceTheme

    var body: some View {
        ZStack {
            AlpSpaceBackgroundView(theme: theme)

            RadialGradient(
                colors: [Color.white.opacity(0.20), Color.white.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.30),
                startRadius: 0,
                endRadius: 560
            )

            GeometryReader { geo in
                let glyphWidth = min(geo.size.width * 0.62, 720)
                ZStack(alignment: .bottom) {
                    StartPageMountainGlyph()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: glyphWidth, height: glyphWidth * 0.52)
                        .padding(.bottom, geo.size.height * 0.14)

                    StartPageRidge(heights: [0.30, 0.52, 0.38, 0.66, 0.44, 0.58, 0.34, 0.50, 0.28])
                        .fill(theme.primaryColor.darkened(by: 0.35).swiftUIColor.opacity(0.16))
                        .frame(height: geo.size.height * 0.30)

                    StartPageRidge(heights: [0.22, 0.34, 0.26, 0.44, 0.30, 0.38, 0.24, 0.40, 0.20])
                        .fill(theme.primaryColor.darkened(by: 0.55).swiftUIColor.opacity(0.24))
                        .frame(height: geo.size.height * 0.20)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }

            StartPageGrain(intensity: theme.grainIntensity)
        }
    }
}

/// Two overlapping peaks: the app's mountain mark, drawn as a plain path.
private struct StartPageMountainGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.34, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.62, y: rect.maxY))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.minX + w * 0.42, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.72, y: rect.minY + h * 0.34))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A jagged skyline filling the bottom of its rect; `heights` are 0...1 fractions, evenly spaced.
private struct StartPageRidge: Shape {
    let heights: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard heights.count > 1 else { return path }
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (index, fraction) in heights.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(heights.count - 1)
            path.addLine(to: CGPoint(x: x, y: rect.maxY - rect.height * fraction))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Fixed-seed speckle so the grain is identical on every launch and costs no assets.
private struct StartPageGrain: View {
    let intensity: Double

    var body: some View {
        Canvas { context, size in
            let strength = min(max(intensity, 0), 1)
            let count = min(7000, Int(size.width * size.height / 240))
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func nextUnit() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 11) / 9_007_199_254_740_992.0
            }
            for _ in 0..<count {
                let x = nextUnit() * size.width
                let y = nextUnit() * size.height
                let light = nextUnit() > 0.5
                let alpha = (0.05 + 0.09 * nextUnit()) * (0.4 + strength)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color((light ? Color.white : Color.black).opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
