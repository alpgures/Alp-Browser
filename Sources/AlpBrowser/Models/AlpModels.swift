//
//  AlpModels.swift
//  Alp Browser
//
//  Clean-room implementation of browser domain models.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import SwiftUI
import AppKit

// MARK: - Color & Visual Theme Models

public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    public init(nsColor: NSColor) {
        let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(srgb.redComponent)
        self.green = Double(srgb.greenComponent)
        self.blue = Double(srgb.blueComponent)
        self.alpha = Double(srgb.alphaComponent)
    }

    public init(color: Color) {
        self.init(nsColor: NSColor(color))
    }

    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1.0) {
        let ns = NSColor(
            hue: CGFloat(min(max(hue, 0), 1)),
            saturation: CGFloat(min(max(saturation, 0), 1)),
            brightness: CGFloat(min(max(brightness, 0), 1)),
            alpha: CGFloat(alpha)
        ).usingColorSpace(.sRGB) ?? .white

        self.red = Double(ns.redComponent)
        self.green = Double(ns.greenComponent)
        self.blue = Double(ns.blueComponent)
        self.alpha = Double(ns.alphaComponent)
    }

    public init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgb = UInt64(cleanHex, radix: 16) else { return nil }
        self.red = Double((rgb >> 16) & 0xFF) / 255.0
        self.green = Double((rgb >> 8) & 0xFF) / 255.0
        self.blue = Double(rgb & 0xFF) / 255.0
        self.alpha = 1.0
    }

    public var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let ns = nsColor.usingColorSpace(.sRGB) ?? nsColor
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }

    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    public func blended(with other: RGBAColor, fraction: Double) -> RGBAColor {
        let f = min(max(fraction, 0), 1)
        return RGBAColor(
            red: red + (other.red - red) * f,
            green: green + (other.green - green) * f,
            blue: blue + (other.blue - blue) * f,
            alpha: alpha + (other.alpha - alpha) * f
        )
    }

    public func darkened(by amount: Double = 0.25) -> RGBAColor {
        blended(with: RGBAColor(red: 0.03, green: 0.04, blue: 0.05, alpha: alpha), fraction: amount)
    }

    public func lightened(by amount: Double = 0.25) -> RGBAColor {
        blended(with: RGBAColor(red: 0.97, green: 0.98, blue: 0.99, alpha: alpha), fraction: amount)
    }
}

public struct SpaceTheme: Codable, Equatable, Hashable, Sendable {
    public var primaryColor: RGBAColor
    public var secondaryColor: RGBAColor
    public var accentColor: RGBAColor
    public var colorStops: [RGBAColor]
    public var isVibrant: Bool
    public var grainIntensity: Double
    public var intensityFactor: Double
    public var prefersLightForeground: Bool

    public init(
        primaryColor: RGBAColor,
        secondaryColor: RGBAColor? = nil,
        accentColor: RGBAColor? = nil,
        colorStops: [RGBAColor]? = nil,
        isVibrant: Bool = true,
        grainIntensity: Double = 0.65,
        intensityFactor: Double = 0.29,
        prefersLightForeground: Bool = false
    ) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor ?? primaryColor.darkened(by: 0.35)
        self.accentColor = accentColor ?? primaryColor.lightened(by: 0.35)
        self.colorStops = colorStops ?? [primaryColor]
        self.isVibrant = isVibrant
        self.grainIntensity = grainIntensity
        self.intensityFactor = intensityFactor
        self.prefersLightForeground = prefersLightForeground
    }

    /// Computes the frosted gradient colors taking intensity factor and appearance into account.
    public var renderedGradientColors: [Color] {
        let baseStops = colorStops.isEmpty ? [primaryColor] : colorStops
        let intensity = min(max(intensityFactor, 0.05), 1.0)

        if !prefersLightForeground {
            // Light frosted appearance
            let frostedBase = primaryColor.lightened(by: 0.84)
            if baseStops.count == 1 {
                let top = frostedBase.blended(with: primaryColor, fraction: intensity * 0.95)
                let bottom = frostedBase.blended(with: primaryColor, fraction: min(1.0, intensity * 1.35))
                return [top.swiftUIColor, bottom.swiftUIColor]
            } else {
                return baseStops.map { stop in
                    let lightBase = stop.lightened(by: 0.82)
                    return lightBase.blended(with: stop, fraction: min(1.0, intensity * 1.15)).swiftUIColor
                }
            }
        } else {
            // Dark appearance
            let darkBase = primaryColor.darkened(by: 0.72)
            if baseStops.count == 1 {
                let top = darkBase.blended(with: primaryColor, fraction: intensity * 0.92)
                let bottom = darkBase.blended(with: secondaryColor, fraction: intensity * 0.75)
                return [top.swiftUIColor, bottom.swiftUIColor]
            } else {
                return baseStops.map { stop in
                    let deep = stop.darkened(by: 0.65)
                    return deep.blended(with: stop, fraction: intensity * 0.90).swiftUIColor
                }
            }
        }
    }

    public var foregroundColor: Color {
        if prefersLightForeground {
            return primaryColor.lightened(by: 0.86).swiftUIColor
        } else {
            return primaryColor.darkened(by: 0.82).swiftUIColor
        }
    }

    public var secondaryForegroundColor: Color {
        if prefersLightForeground {
            return primaryColor.lightened(by: 0.58).swiftUIColor.opacity(0.78)
        } else {
            return primaryColor.darkened(by: 0.62).swiftUIColor.opacity(0.72)
        }
    }

    public var effectiveAccentColor: Color {
        if prefersLightForeground {
            return accentColor.lightened(by: 0.20).swiftUIColor
        } else {
            return primaryColor.darkened(by: 0.45).swiftUIColor
        }
    }

    public var selectionBackground: Color {
        if prefersLightForeground {
            return Color.white.opacity(0.20)
        } else {
            return Color.white.opacity(0.92)
        }
    }

    public var hoverBackground: Color {
        if prefersLightForeground {
            return Color.white.opacity(0.10)
        } else {
            return primaryColor.darkened(by: 0.35).swiftUIColor.opacity(0.12)
        }
    }

    public var pillBackground: Color {
        if prefersLightForeground {
            return Color.white.opacity(0.14)
        } else {
            return Color.white.opacity(0.50)
        }
    }

    public var pillBorderColor: Color {
        if prefersLightForeground {
            return Color.white.opacity(0.18)
        } else {
            return primaryColor.darkened(by: 0.40).swiftUIColor.opacity(0.18)
        }
    }

    // MARK: - Theme Presets

    public static let userPersonalSky = SpaceTheme(
        primaryColor: RGBAColor(red: 0.4236, green: 0.7286, blue: 0.8512),
        secondaryColor: RGBAColor(red: 0.0010, green: 0.3744, blue: 0.4910),
        accentColor: RGBAColor(red: 0.8947, green: 0.9490, blue: 0.9723),
        colorStops: [RGBAColor(red: 0.4236, green: 0.7286, blue: 0.8512)],
        isVibrant: true,
        grainIntensity: 0.65,
        intensityFactor: 0.288,
        prefersLightForeground: false
    )

    public static let userLeisurePlum = SpaceTheme(
        primaryColor: RGBAColor(red: 0.3273, green: 0.2741, blue: 0.3695),
        secondaryColor: RGBAColor(red: 0.1900, green: 0.1500, blue: 0.2200),
        accentColor: RGBAColor(red: 0.6291, green: 0.5656, blue: 0.6794),
        colorStops: [RGBAColor(red: 0.3273, green: 0.2741, blue: 0.3695)],
        isVibrant: true,
        grainIntensity: 0.95,
        intensityFactor: 1.0,
        prefersLightForeground: true
    )

    public static let userPersonalSkyDark = SpaceTheme(
        primaryColor: RGBAColor(red: 0.0010, green: 0.3744, blue: 0.4910),
        secondaryColor: RGBAColor(red: 0.0003, green: 0.1123, blue: 0.1473),
        accentColor: RGBAColor(red: 0.4236, green: 0.7286, blue: 0.8512),
        colorStops: [
            RGBAColor(red: 0.0010, green: 0.3744, blue: 0.4910),
            RGBAColor(red: 0.4236, green: 0.7286, blue: 0.8512)
        ],
        isVibrant: true,
        grainIntensity: 0.65,
        intensityFactor: 0.75,
        prefersLightForeground: true
    )

    public static let auroraMesh = SpaceTheme(
        primaryColor: RGBAColor(red: 0.38, green: 0.69, blue: 0.88),
        secondaryColor: RGBAColor(red: 0.56, green: 0.38, blue: 0.84),
        accentColor: RGBAColor(red: 0.36, green: 0.89, blue: 0.76),
        colorStops: [
            RGBAColor(red: 0.38, green: 0.69, blue: 0.88),
            RGBAColor(red: 0.56, green: 0.38, blue: 0.84),
            RGBAColor(red: 0.36, green: 0.89, blue: 0.76)
        ],
        isVibrant: true,
        grainIntensity: 0.50,
        intensityFactor: 0.38,
        prefersLightForeground: false
    )

    public static let warmSunset = SpaceTheme(
        primaryColor: RGBAColor(red: 0.88, green: 0.44, blue: 0.52),
        secondaryColor: RGBAColor(red: 0.48, green: 0.24, blue: 0.46),
        accentColor: RGBAColor(red: 0.98, green: 0.68, blue: 0.45),
        colorStops: [
            RGBAColor(red: 0.88, green: 0.44, blue: 0.52),
            RGBAColor(red: 0.98, green: 0.68, blue: 0.45)
        ],
        isVibrant: true,
        grainIntensity: 0.55,
        intensityFactor: 0.42,
        prefersLightForeground: false
    )

    public static let forestEmerald = SpaceTheme(
        primaryColor: RGBAColor(red: 0.12, green: 0.45, blue: 0.32),
        secondaryColor: RGBAColor(red: 0.05, green: 0.22, blue: 0.16),
        accentColor: RGBAColor(red: 0.42, green: 0.88, blue: 0.65),
        colorStops: [
            RGBAColor(red: 0.12, green: 0.45, blue: 0.32),
            RGBAColor(red: 0.22, green: 0.65, blue: 0.48)
        ],
        isVibrant: true,
        grainIntensity: 0.60,
        intensityFactor: 0.45,
        prefersLightForeground: true
    )

    public static let velvetRose = SpaceTheme(
        primaryColor: RGBAColor(red: 0.76, green: 0.20, blue: 0.42),
        secondaryColor: RGBAColor(red: 0.38, green: 0.08, blue: 0.20),
        accentColor: RGBAColor(red: 0.98, green: 0.55, blue: 0.72),
        colorStops: [
            RGBAColor(red: 0.76, green: 0.20, blue: 0.42),
            RGBAColor(red: 0.50, green: 0.15, blue: 0.58)
        ],
        isVibrant: true,
        grainIntensity: 0.70,
        intensityFactor: 0.50,
        prefersLightForeground: true
    )

    public static let presets: [(name: String, subtitle: String, theme: SpaceTheme)] = [
        ("Personal Sky", "Frosted Ice Blue (Light)", .userPersonalSky),
        ("Leisure Plum", "Deep Amethyst (Dark)", .userLeisurePlum),
        ("Deep Cerulean", "Ocean Dark (Dark)", .userPersonalSkyDark),
        ("Aurora Mesh", "3-Tone Pastel", .auroraMesh),
        ("Warm Sunset", "2-Tone Coral", .warmSunset),
        ("Forest Emerald", "Alpine Pine Glass", .forestEmerald),
        ("Velvet Rose", "Magenta & Orchid", .velvetRose)
    ]
}

public enum SpaceThemeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case single = "Single Color"
    case dualGradient = "Dual Gradient"
    case multiMesh = "3-Stop Mesh"

    public var id: String { rawValue }
}

// MARK: - Tab & Sidebar Hierarchy Models

public enum TabKind: Codable, Equatable, Hashable, Sendable {
    case web
    case canvas(UUID)
    case note(UUID)
}

public struct TabItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var customTitle: String?
    public var urlString: String
    public var pinnedURLString: String?
    public var isFavorite: Bool
    public var isPinned: Bool
    public var isHibernated: Bool
    public var isMuted: Bool
    public var isPlayingAudio: Bool
    public var isLoading: Bool
    public var estimatedProgress: Double
    public var createdAt: Date
    public var lastActiveAt: Date
    public var kind: TabKind
    public var todayCategory: String?

    public init(
        id: UUID = UUID(),
        title: String,
        customTitle: String? = nil,
        urlString: String,
        pinnedURLString: String? = nil,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        isHibernated: Bool = false,
        isMuted: Bool = false,
        isPlayingAudio: Bool = false,
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        kind: TabKind = .web,
        todayCategory: String? = nil
    ) {
        self.id = id
        self.title = title
        self.customTitle = customTitle
        self.urlString = urlString
        self.pinnedURLString = pinnedURLString ?? (isPinned ? urlString : nil)
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isHibernated = isHibernated
        self.isMuted = isMuted
        self.isPlayingAudio = isPlayingAudio
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.kind = kind
        self.todayCategory = todayCategory
    }

    public var displayTitle: String {
        if let custom = customTitle, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return simplifiedDomain
    }

    public var simplifiedDomain: String {
        if urlString.lowercased().hasPrefix("chrome-extension://") {
            return "Extension"
        }
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var hasNavigatedAwayFromPin: Bool {
        guard isPinned, let pinned = pinnedURLString else { return false }
        return normalizeURL(urlString) != normalizeURL(pinned)
    }

    public var isSecure: Bool {
        urlString.lowercased().hasPrefix("https://")
    }

    public var faviconURL: URL? {
        guard kind == .web, let url = URL(string: urlString), let host = url.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    private func normalizeURL(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed.lowercased()
    }
}

public struct FolderItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isExpanded: Bool
    public var children: [SidebarNode]

    public init(
        id: UUID = UUID(),
        title: String,
        isExpanded: Bool = false,
        children: [SidebarNode] = []
    ) {
        self.id = id
        self.title = title
        self.isExpanded = isExpanded
        self.children = children
    }
}

public enum SidebarNode: Identifiable, Codable, Equatable, Hashable, Sendable {
    case tab(TabItem)
    case folder(FolderItem)

    public var id: UUID {
        switch self {
        case .tab(let tab): return tab.id
        case .folder(let folder): return folder.id
        }
    }

    public var allTabs: [TabItem] {
        switch self {
        case .tab(let tab):
            return [tab]
        case .folder(let folder):
            return folder.children.flatMap { $0.allTabs }
        }
    }
}

public enum SplitOrientation: String, Codable, Equatable, Hashable, Sendable {
    case horizontal
    case vertical
}

// MARK: - Space Model

public struct AlpSpace: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var originalArcID: String?
    public var title: String
    public var iconEmoji: String
    public var profileName: String
    public var theme: SpaceTheme
    public var pinnedNodes: [SidebarNode]
    public var todayTabs: [TabItem]
    public var activeTabID: UUID?
    public var splitPaneTabIDs: [UUID]
    public var splitOrientation: SplitOrientation

    public init(
        id: UUID = UUID(),
        originalArcID: String? = nil,
        title: String,
        iconEmoji: String = "✨",
        profileName: String = "Default",
        theme: SpaceTheme = .userPersonalSky,
        pinnedNodes: [SidebarNode] = [],
        todayTabs: [TabItem] = [],
        activeTabID: UUID? = nil,
        splitPaneTabIDs: [UUID] = [],
        splitOrientation: SplitOrientation = .horizontal
    ) {
        self.id = id
        self.originalArcID = originalArcID
        self.title = title
        self.iconEmoji = iconEmoji
        self.profileName = profileName
        self.theme = theme
        self.pinnedNodes = pinnedNodes
        self.todayTabs = todayTabs
        self.activeTabID = activeTabID
        self.splitPaneTabIDs = splitPaneTabIDs
        self.splitOrientation = splitOrientation
    }

    public var allPinnedTabs: [TabItem] {
        pinnedNodes.flatMap { $0.allTabs }
    }

    public var allTabs: [TabItem] {
        allPinnedTabs + todayTabs
    }
}

// MARK: - Page Mod / Alp Style Model

public struct PageMod: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var domain: String
    public var name: String
    public var isEnabled: Bool
    public var tintColor: RGBAColor?
    public var hueRotateDegrees: Double
    public var brightness: Double
    public var contrast: Double
    public var saturate: Double
    public var invertColors: Bool
    public var fontFamily: String?
    public var fontScalePercent: Double
    public var zappedSelectors: [String]
    public var customCSS: String
    public var customJS: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        domain: String,
        name: String = "Custom Style",
        isEnabled: Bool = true,
        tintColor: RGBAColor? = nil,
        hueRotateDegrees: Double = 0,
        brightness: Double = 1.0,
        contrast: Double = 1.0,
        saturate: Double = 1.0,
        invertColors: Bool = false,
        fontFamily: String? = nil,
        fontScalePercent: Double = 100,
        zappedSelectors: [String] = [],
        customCSS: String = "",
        customJS: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.domain = domain
        self.name = name
        self.isEnabled = isEnabled
        self.tintColor = tintColor
        self.hueRotateDegrees = hueRotateDegrees
        self.brightness = brightness
        self.contrast = contrast
        self.saturate = saturate
        self.invertColors = invertColors
        self.fontFamily = fontFamily
        self.fontScalePercent = fontScalePercent
        self.zappedSelectors = zappedSelectors
        self.customCSS = customCSS
        self.customJS = customJS
        self.updatedAt = updatedAt
    }

    public var compiledCSS: String {
        var rules: [String] = []

        var filters: [String] = []
        if abs(hueRotateDegrees) > 0.5 {
            filters.append("hue-rotate(\(Int(hueRotateDegrees))deg)")
        }
        if abs(brightness - 1.0) > 0.02 {
            filters.append(String(format: "brightness(%.2f)", brightness))
        }
        if abs(contrast - 1.0) > 0.02 {
            filters.append(String(format: "contrast(%.2f)", contrast))
        }
        if abs(saturate - 1.0) > 0.02 {
            filters.append(String(format: "saturate(%.2f)", saturate))
        }
        if invertColors {
            filters.append("invert(1) hue-rotate(180deg)")
        }
        if !filters.isEmpty {
            rules.append("html { filter: \(filters.joined(separator: " ")) !important; }")
        }

        if let font = fontFamily, !font.isEmpty {
            rules.append("body, p, span, a, li, h1, h2, h3, h4, h5, h6, div { font-family: '\(font)', -apple-system, sans-serif !important; }")
        }

        if abs(fontScalePercent - 100) > 1 {
            rules.append("html { zoom: \(Int(fontScalePercent))% !important; }")
        }

        if let tint = tintColor {
            let r = Int(tint.red * 255)
            let g = Int(tint.green * 255)
            let b = Int(tint.blue * 255)
            rules.append("""
            body::after {
                content: '';
                position: fixed;
                inset: 0;
                pointer-events: none;
                z-index: 2147483646;
                background: rgba(\(r), \(g), \(b), 0.14);
                mix-blend-mode: multiply;
            }
            """)
        }

        if !zappedSelectors.isEmpty {
            let joined = zappedSelectors.joined(separator: ", ")
            rules.append("\(joined) { display: none !important; visibility: hidden !important; }")
        }

        if !customCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rules.append(customCSS)
        }

        return rules.joined(separator: "\n")
    }
}

// MARK: - Canvas & Notes Models

public enum AlpCanvasElementKind: String, Codable, Equatable, Hashable, Sendable {
    case stickyNote
    case textHeader
    case webCard
    case codeSnippet
    case image
}

public struct AlpCanvasElement: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var kind: AlpCanvasElementKind
    public var text: String
    public var urlString: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var color: RGBAColor

    public init(
        id: UUID = UUID(),
        kind: AlpCanvasElementKind = .stickyNote,
        text: String,
        urlString: String? = nil,
        x: Double = 140,
        y: Double = 140,
        width: Double = 240,
        height: Double = 160,
        color: RGBAColor = RGBAColor(red: 0.98, green: 0.89, blue: 0.48)
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.urlString = urlString
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.color = color
    }
}

public struct AlpCanvas: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var elements: [AlpCanvasElement]

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Canvas",
        updatedAt: Date = Date(),
        elements: [AlpCanvasElement] = []
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.elements = elements
    }
}

public struct AlpNote: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Note",
        body: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }
}

// MARK: - Archive & History Models

public struct ArchivedTab: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var urlString: String
    public var spaceTitle: String
    public var archivedAt: Date
    public var reason: String

    public init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        spaceTitle: String,
        archivedAt: Date = Date(),
        reason: String = "Auto-Archive (12h)"
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.spaceTitle = spaceTitle
        self.archivedAt = archivedAt
        self.reason = reason
    }
}

// MARK: - Peek Session

public struct PeekSession: Identifiable, Equatable {
    public let id = UUID()
    public var urlString: String
    public var title: String
    public var sourceTabID: UUID?

    public init(urlString: String, title: String, sourceTabID: UUID? = nil) {
        self.urlString = urlString
        self.title = title
        self.sourceTabID = sourceTabID
    }
}

// MARK: - Sync Configuration (Generic Privacy-Preserving Cloud Sync)

public struct AlpSyncConfig: Codable, Equatable, Sendable {
    public var syncEndpointURL: String
    public var syncVaultID: String
    public var autoSyncEnabled: Bool
    public var lastSyncedAt: Date?

    public init(
        syncEndpointURL: String = "http://127.0.0.1:8788",
        syncVaultID: String = "primary",
        autoSyncEnabled: Bool = true,
        lastSyncedAt: Date? = nil
    ) {
        self.syncEndpointURL = syncEndpointURL
        self.syncVaultID = syncVaultID
        self.autoSyncEnabled = autoSyncEnabled
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - Custom App Icon Studio Configuration

public struct CustomIconConfig: Codable, Equatable, Sendable {
    public var startColorHex: String
    public var endColorHex: String
    public var bgMode: Int // 0: Dark, 1: Light, 2: Custom
    public var bgColorHex: String
    public var grain: Double
    public var customImagePath: String?

    public init(
        startColorHex: String = "#FA6138",
        endColorHex: String = "#D11AD9",
        bgMode: Int = 0,
        bgColorHex: String = "#1E1E1E",
        grain: Double = 0.35,
        customImagePath: String? = nil
    ) {
        self.startColorHex = startColorHex
        self.endColorHex = endColorHex
        self.bgMode = bgMode
        self.bgColorHex = bgColorHex
        self.grain = grain
        self.customImagePath = customImagePath
    }
}

// MARK: - Root Persisted Browser Store

public struct PersistedBrowserStore: Codable {
    public var spaces: [AlpSpace]
    public var favorites: [TabItem]
    public var activeSpaceID: UUID?
    public var styles: [PageMod]
    public var canvases: [AlpCanvas]
    public var notes: [AlpNote]
    public var archivedTabs: [ArchivedTab]
    public var autoArchiveHours: Double
    public var autoHibernateMinutes: Double
    public var adBlockerEnabled: Bool
    public var syncConfig: AlpSyncConfig
    public var hasImportedFromArc: Bool
    public var selectedIconName: String
    public var customIconConfig: CustomIconConfig
    public var sidebarWidth: Double

    public init(
        spaces: [AlpSpace] = [],
        favorites: [TabItem] = [],
        activeSpaceID: UUID? = nil,
        styles: [PageMod] = [],
        canvases: [AlpCanvas] = [],
        notes: [AlpNote] = [],
        archivedTabs: [ArchivedTab] = [],
        autoArchiveHours: Double = 12.0,
        autoHibernateMinutes: Double = 5.0,
        adBlockerEnabled: Bool = true,
        syncConfig: AlpSyncConfig = AlpSyncConfig(),
        hasImportedFromArc: Bool = false,
        selectedIconName: String = "alp_browser_original",
        customIconConfig: CustomIconConfig = CustomIconConfig(),
        sidebarWidth: Double = 256.0
    ) {
        self.spaces = spaces
        self.favorites = favorites
        self.activeSpaceID = activeSpaceID
        self.styles = styles
        self.canvases = canvases
        self.notes = notes
        self.archivedTabs = archivedTabs
        self.autoArchiveHours = autoArchiveHours
        self.autoHibernateMinutes = autoHibernateMinutes
        self.adBlockerEnabled = adBlockerEnabled
        self.syncConfig = syncConfig
        self.hasImportedFromArc = hasImportedFromArc
        self.selectedIconName = selectedIconName
        self.customIconConfig = customIconConfig
        self.sidebarWidth = sidebarWidth
    }

    enum CodingKeys: String, CodingKey {
        case spaces, favorites, activeSpaceID, styles, canvases, notes, archivedTabs
        case autoArchiveHours, autoHibernateMinutes, adBlockerEnabled, syncConfig, hasImportedFromArc, selectedIconName
        case customIconConfig, sidebarWidth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.spaces = try container.decodeIfPresent([AlpSpace].self, forKey: .spaces) ?? []
        self.favorites = try container.decodeIfPresent([TabItem].self, forKey: .favorites) ?? []
        self.activeSpaceID = try container.decodeIfPresent(UUID.self, forKey: .activeSpaceID)
        self.styles = try container.decodeIfPresent([PageMod].self, forKey: .styles) ?? []
        self.canvases = try container.decodeIfPresent([AlpCanvas].self, forKey: .canvases) ?? []
        self.notes = try container.decodeIfPresent([AlpNote].self, forKey: .notes) ?? []
        self.archivedTabs = try container.decodeIfPresent([ArchivedTab].self, forKey: .archivedTabs) ?? []
        self.autoArchiveHours = try container.decodeIfPresent(Double.self, forKey: .autoArchiveHours) ?? 12.0
        self.autoHibernateMinutes = try container.decodeIfPresent(Double.self, forKey: .autoHibernateMinutes) ?? 5.0
        self.adBlockerEnabled = try container.decodeIfPresent(Bool.self, forKey: .adBlockerEnabled) ?? true
        self.syncConfig = try container.decodeIfPresent(AlpSyncConfig.self, forKey: .syncConfig) ?? AlpSyncConfig()
        self.hasImportedFromArc = try container.decodeIfPresent(Bool.self, forKey: .hasImportedFromArc) ?? false
        self.selectedIconName = try container.decodeIfPresent(String.self, forKey: .selectedIconName) ?? "alp_browser_original"
        self.customIconConfig = try container.decodeIfPresent(CustomIconConfig.self, forKey: .customIconConfig) ?? CustomIconConfig()
        self.sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 256.0
    }
}
