import Foundation
import SwiftUI
import AppKit

// MARK: - Color & Theme Models

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

    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1.0) {
        let ns = NSColor(hue: CGFloat(min(max(hue, 0), 1)),
                         saturation: CGFloat(min(max(saturation, 0), 1)),
                         brightness: CGFloat(min(max(brightness, 0), 1)),
                         alpha: CGFloat(alpha)).usingColorSpace(.sRGB) ?? .white
        self.red = Double(ns.redComponent)
        self.green = Double(ns.greenComponent)
        self.blue = Double(ns.blueComponent)
        self.alpha = Double(ns.alphaComponent)
    }

    public init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        self.red = Double((rgb >> 16) & 0xFF) / 255.0
        self.green = Double((rgb >> 8) & 0xFF) / 255.0
        self.blue = Double(rgb & 0xFF) / 255.0
        self.alpha = 1.0
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
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

    /// Computes the actual rendered background stops taking Arc's `intensityFactor` and Light/Dark mode into account.
    public var renderedGradientColors: [Color] {
        let baseStops = colorStops.isEmpty ? [primaryColor] : colorStops
        let intensity = min(max(intensityFactor, 0.05), 1.0)

        if !prefersLightForeground {
            // Arc Light Appearance (e.g. Personal Space: #6CBAD9 blended at 28.8% intensity with frosted #EBF5F9)
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
            // Arc Dark Appearance (e.g. Leisure Space: #53465E at 100% intensity)
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

    /// Deep tinted text for Light mode (`#001C26` in Personal space) or crisp light text for Dark mode (`#E5E3E7` in Leisure space).
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
            return Color.white.opacity(0.18)
        } else {
            return primaryColor.darkened(by: 0.30).swiftUIColor.opacity(0.22)
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
            return Color.white.opacity(0.13)
        } else {
            return Color.white.opacity(0.52)
        }
    }

    public var pillBorderColor: Color {
        if prefersLightForeground {
            return Color.white.opacity(0.18)
        } else {
            return primaryColor.darkened(by: 0.40).swiftUIColor.opacity(0.18)
        }
    }

    // MARK: - User's Exact Arc Config Themes (from StorableSidebar.json)

    /// Exact theme from user's "Personal" (🧌) space in Arc:
    /// Color: red 0.4236, green 0.7286, blue 0.8512 (#6CBAD9)
    /// Appearance: Light, intensityFactor: 0.288, noiseFactor: 0.65
    public static let userPersonalSky = SpaceTheme(
        primaryColor: RGBAColor(red: 0.42361512780189514, green: 0.7285773754119873, blue: 0.8512415885925293),
        secondaryColor: RGBAColor(red: 0.0008414909825660288, green: 0.3744068741798401, blue: 0.49104613065719604),
        accentColor: RGBAColor(red: 0.8946989178657532, green: 0.9489534497261047, blue: 0.9722734093666077),
        colorStops: [
            RGBAColor(red: 0.42361512780189514, green: 0.7285773754119873, blue: 0.8512415885925293)
        ],
        isVibrant: true,
        grainIntensity: 0.65,
        intensityFactor: 0.2880805071246524,
        prefersLightForeground: false // "contentOverBackgroundAppearance": "light" in Arc!
    )

    /// Exact theme from user's "Leisure" (👹) space in Arc:
    /// Color: red 0.3273, green 0.2741, blue 0.3695 (#53465E), midTone: #A090AD
    /// Appearance: Dark, intensityFactor: 1.0, noiseFactor: 0.95
    public static let userLeisurePlum = SpaceTheme(
        primaryColor: RGBAColor(red: 0.3272783160209656, green: 0.2741466164588928, blue: 0.3694503903388977),
        secondaryColor: RGBAColor(red: 0.19, green: 0.15, blue: 0.22),
        accentColor: RGBAColor(red: 0.6291168332099915, green: 0.5655614733695984, blue: 0.6793941259384155),
        colorStops: [
            RGBAColor(red: 0.3272783160209656, green: 0.2741466164588928, blue: 0.3694503903388977)
        ],
        isVibrant: true,
        grainIntensity: 0.95,
        intensityFactor: 1.0,
        prefersLightForeground: true // "contentOverBackgroundAppearance": "dark" in Arc!
    )

    /// Personal Sky in Dark Mode variant (using Arc's dark semanticColorPalette for #6CBAD9)
    public static let userPersonalSkyDark = SpaceTheme(
        primaryColor: RGBAColor(red: 0.0008414909825660288, green: 0.3744068741798401, blue: 0.49104613065719604),
        secondaryColor: RGBAColor(red: 0.0002524472074583173, green: 0.11232205480337143, blue: 0.14731381833553314),
        accentColor: RGBAColor(red: 0.42361512780189514, green: 0.7285773754119873, blue: 0.8512415885925293),
        colorStops: [
            RGBAColor(red: 0.0008414909825660288, green: 0.3744068741798401, blue: 0.49104613065719604),
            RGBAColor(red: 0.42361512780189514, green: 0.7285773754119873, blue: 0.8512415885925293)
        ],
        isVibrant: true,
        grainIntensity: 0.65,
        intensityFactor: 0.75,
        prefersLightForeground: true
    )

    public static let arcAurora = SpaceTheme(
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

    public static let arcSunset = SpaceTheme(
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

    public static let arcPurple = userPersonalSky
    public static let arcSlate = userLeisurePlum

    public static let presets: [(name: String, subtitle: String, theme: SpaceTheme)] = [
        ("Personal Sky", "Your Arc #6CBAD9 (Light)", .userPersonalSky),
        ("Leisure Plum", "Your Arc #53465E (Dark)", .userLeisurePlum),
        ("Deep Cerulean", "Your #6CBAD9 (Dark)", .userPersonalSkyDark),
        ("Aurora Mesh", "3-Tone Pastel", .arcAurora),
        ("Warm Sunset", "2-Tone Coral", .arcSunset)
    ]
}

// MARK: - Tabs, Folders & Sidebar Tree

public enum TabKind: Codable, Equatable, Hashable, Sendable {
    case web
    case easel(UUID)
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
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var hasNavigatedAwayFromPin: Bool {
        guard isPinned, let pinned = pinnedURLString else { return false }
        return normalizeURL(urlString) != normalizeURL(pinned)
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
        isExpanded: Bool = true,
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

public struct ArcSpace: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var arcOriginalID: String?
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
        arcOriginalID: String? = nil,
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
        self.arcOriginalID = arcOriginalID
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

// MARK: - Boosts 2.0 Model

public struct ArcBoost: Identifiable, Codable, Equatable, Hashable, Sendable {
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
        name: String = "Custom Boost",
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

// MARK: - Easels & Notes Models

public enum EaselElementKind: String, Codable, Equatable, Hashable, Sendable {
    case stickyNote
    case textHeader
    case webCard
    case codeSnippet
}

public struct EaselElement: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var kind: EaselElementKind
    public var text: String
    public var urlString: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var color: RGBAColor

    public init(
        id: UUID = UUID(),
        kind: EaselElementKind = .stickyNote,
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

public struct ArcEasel: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var elements: [EaselElement]

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Easel",
        updatedAt: Date = Date(),
        elements: [EaselElement] = []
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.elements = elements
    }
}

public struct ArcNote: Identifiable, Codable, Equatable, Hashable, Sendable {
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

// MARK: - Peek & OCI Sync Config

public struct PeekSession: Identifiable, Equatable {
    public let id = UUID()
    public var urlString: String
    public var title: String
    public var sourceTabID: UUID?
}

public struct OCICloudConfig: Codable, Equatable, Sendable {
    public var host: String
    public var sshHostAlias: String
    public var syncEndpointURL: String
    public var autoSyncEnabled: Bool
    public var useOCIClaudeForArcMax: Bool
    public var lastSyncedAt: Date?

    public init(
        host: String = "150.136.50.234",
        sshHostAlias: String = "oci-box",
        syncEndpointURL: String = "http://150.136.50.234:8765",
        autoSyncEnabled: Bool = true,
        useOCIClaudeForArcMax: Bool = true,
        lastSyncedAt: Date? = nil
    ) {
        self.host = host
        self.sshHostAlias = sshHostAlias
        self.syncEndpointURL = syncEndpointURL
        self.autoSyncEnabled = autoSyncEnabled
        self.useOCIClaudeForArcMax = useOCIClaudeForArcMax
        self.lastSyncedAt = lastSyncedAt
    }
}

public struct PersistedBrowserStore: Codable {
    public var spaces: [ArcSpace]
    public var favorites: [TabItem]
    public var activeSpaceID: UUID?
    public var boosts: [ArcBoost]
    public var easels: [ArcEasel]
    public var notes: [ArcNote]
    public var archivedTabs: [ArchivedTab]
    public var autoArchiveHours: Double
    public var autoHibernateMinutes: Double
    public var adBlockerEnabled: Bool
    public var ociConfig: OCICloudConfig
    public var hasImportedFromArc: Bool
}
