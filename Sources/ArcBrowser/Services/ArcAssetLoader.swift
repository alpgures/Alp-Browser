import Foundation
import AppKit
import CoreText
import AVFoundation

@MainActor
public final class ArcAssetLoader {
    public static let shared = ArcAssetLoader()

    public private(set) var windowThemeBundle: Bundle?
    public private(set) var spaceStyleBundle: Bundle?
    public private(set) var soundEffectsBundle: Bundle?
    public private(set) var fontsBundle: Bundle?

    private var cachedTextures: [String: NSImage] = [:]
    private var audioPlayer: AVAudioPlayer?

    private init() {
        windowThemeBundle = Self.findBundle(named: "ARC_WindowThemeUI.bundle")
        spaceStyleBundle = Self.findBundle(named: "ARC_SpaceStyleEditor.bundle")
        soundEffectsBundle = Self.findBundle(named: "ARC_SoundEffects.bundle")
        fontsBundle = Self.findBundle(named: "ARCClients_FontsManager.bundle")
        registerArcFonts()
    }

    private static func findBundle(named bundleName: String) -> Bundle? {
        // 1. Check inside Arc2.app/Contents/Resources/ first
        if let localPath = Bundle.main.resourcePath {
            let candidate = (localPath as NSString).appendingPathComponent(bundleName)
            if let b = Bundle(path: candidate) {
                return b
            }
        }
        // 2. Fallback to /Applications/Arc.app/Contents/Resources/
        let installedPath = "/Applications/Arc.app/Contents/Resources/\(bundleName)"
        return Bundle(path: installedPath)
    }

    /// Loads Arc's authentic texture image ("grain", "denim", "sand", "tweed") from `ARC_WindowThemeUI.bundle/Assets.car`.
    public func textureImage(named name: String = "grain") -> NSImage? {
        if let cached = cachedTextures[name] {
            return cached
        }
        if let img = windowThemeBundle?.image(forResource: NSImage.Name(name)) {
            cachedTextures[name] = img
            return img
        }
        return nil
    }

    /// Loads Arc's authentic `DotGrid` image from `ARC_SpaceStyleEditor.bundle/Assets.car`.
    public func spaceStyleImage(named name: String) -> NSImage? {
        if let cached = cachedTextures["style_\(name)"] {
            return cached
        }
        if let img = spaceStyleBundle?.image(forResource: NSImage.Name(name)) {
            cachedTextures["style_\(name)"] = img
            return img
        }
        return nil
    }

    /// Loads Arc's 27 official SpaceStyleEditor swatch colors (`ColorPickerPastel1..9`, `ColorPickerDrab1..9`, `ColorPickerGreyscale1..9`).
    public var arcOfficialColorSwatches: [(group: String, colors: [RGBAColor])] {
        guard let bundle = spaceStyleBundle else { return [] }
        let groups = ["Pastel", "Drab", "Greyscale"]
        var result: [(group: String, colors: [RGBAColor])] = []

        for group in groups {
            var groupColors: [RGBAColor] = []
            for i in 1...9 {
                let assetName = "ColorPicker\(group)\(i)"
                if let nsColor = NSColor(named: NSColor.Name(assetName), bundle: bundle),
                   let srgb = nsColor.usingColorSpace(.sRGB) {
                    groupColors.append(
                        RGBAColor(
                            red: Double(srgb.redComponent),
                            green: Double(srgb.greenComponent),
                            blue: Double(srgb.blueComponent),
                            alpha: Double(srgb.alphaComponent)
                        )
                    )
                }
            }
            if !groupColors.isEmpty {
                result.append((group: group, colors: groupColors))
            }
        }
        return result
    }

    /// Plays Arc's native sound effect ("capture.wav" or "event.m4a").
    public func playArcSound(_ fileName: String) {
        guard let resPath = soundEffectsBundle?.resourcePath else { return }
        let url = URL(fileURLWithPath: resPath).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = 0.5
            player.play()
            self.audioPlayer = player
        }
    }

    private func registerArcFonts() {
        guard let resPath = fontsBundle?.resourcePath,
              let files = try? FileManager.default.contentsOfDirectory(atPath: resPath) else { return }
        for file in files where file.hasSuffix(".otf") || file.hasSuffix(".ttf") {
            let fontURL = URL(fileURLWithPath: resPath).appendingPathComponent(file) as CFURL
            CTFontManagerRegisterFontsForURL(fontURL, .process, nil)
        }
    }
}
