//
//  AlpIconGenerator.swift
//  Alp Browser
//
//  High-fidelity Apple HIG squircle icon generator, custom gradient & grain studio,
//  and dynamic Dock/Finder icon applicator.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import AppKit
import CoreGraphics
import Foundation

@MainActor
public enum AlpIconGenerator {

    /// Loads a bundled `.icns` by resource name from the app bundle only.
    /// Returns nil (caller keeps the current icon) when running unbundled, e.g. `swift run`.
    public static func bundledIcon(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Preset Gradients

    public struct GradientPreset: Identifiable {
        public let id: String
        public let name: String
        public let startHex: String
        public let endHex: String
        public let bgMode: Int
        public let grain: Double

        public init(id: String, name: String, startHex: String, endHex: String, bgMode: Int = 0, grain: Double = 0.35) {
            self.id = id
            self.name = name
            self.startHex = startHex
            self.endHex = endHex
            self.bgMode = bgMode
            self.grain = grain
        }
    }

    public static let presets: [GradientPreset] = [
        GradientPreset(id: "sunset", name: "Sunset", startHex: "#FA6138", endHex: "#D11AD9", bgMode: 0, grain: 0.35),
        GradientPreset(id: "ocean", name: "Ocean", startHex: "#1AB8D9", endHex: "#2E4DF2", bgMode: 0, grain: 0.25),
        GradientPreset(id: "cyber", name: "Cyber", startHex: "#2EFA8C", endHex: "#26A6F2", bgMode: 0, grain: 0.40),
        GradientPreset(id: "neon", name: "Neon", startHex: "#F52796", endHex: "#8627F5", bgMode: 0, grain: 0.30),
        GradientPreset(id: "midnight", name: "Midnight", startHex: "#4C6B94", endHex: "#7C92BF", bgMode: 0, grain: 0.20),
        GradientPreset(id: "alpine_snow", name: "Alpine Snow", startHex: "#2C2C2E", endHex: "#1C1C1E", bgMode: 1, grain: 0.15)
    ]

    // MARK: - Custom Icon Generation

    public static func generateCustomIcon(config: CustomIconConfig) -> NSImage? {
        guard let cgImage = generateCustomIconCG(config: config) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 1024, height: 1024))
    }

    public static func generateCustomIconCG(config: CustomIconConfig) -> CGImage? {
        let w = 1024
        let h = 1024
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let outCtx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        let sqRect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let cornerRadius: CGFloat = 185.0
        let sqPath = CGPath(roundedRect: sqRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // 1. Subtle macOS HIG drop shadow underneath squircle
        outCtx.saveGState()
        let shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.32)
        outCtx.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: shadowColor)
        outCtx.addPath(sqPath)
        outCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
        outCtx.fillPath()
        outCtx.restoreGState()

        // 2. Clip to squircle
        outCtx.saveGState()
        outCtx.addPath(sqPath)
        outCtx.clip()

        // 3. Squircle Background Fill
        let bgColor: NSColor
        switch config.bgMode {
        case 1: // Light
            bgColor = NSColor(calibratedWhite: 0.96, alpha: 1.0)
        case 2: // Custom Color
            bgColor = RGBAColor(hex: config.bgColorHex)?.nsColor ?? NSColor(calibratedWhite: 0.12, alpha: 1.0)
        default: // Dark
            bgColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        }
        let sbg = bgColor.usingColorSpace(.sRGB) ?? bgColor
        outCtx.setFillColor(red: sbg.redComponent, green: sbg.greenComponent, blue: sbg.blueComponent, alpha: 1.0)
        outCtx.fill(sqRect)

        // 4. Logo Layer: Custom Image or Gradient Mountain
        if let customPath = config.customImagePath,
           FileManager.default.fileExists(atPath: customPath),
           let customNS = NSImage(contentsOfFile: customPath),
           let customCg = customNS.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            // Draw user-supplied custom graphic centered
            let insetRect = sqRect.insetBy(dx: 48, dy: 48)
            outCtx.draw(customCg, in: insetRect)
        } else {
            // Mountain Mask with Dual Gradient + Grain
            if let mountainCg = renderMountainWithGradient(config: config, colorSpace: colorSpace) {
                outCtx.draw(mountainCg, in: sqRect)
            }
        }

        outCtx.restoreGState()
        return outCtx.makeImage()
    }

    private static func renderMountainWithGradient(config: CustomIconConfig, colorSpace: CGColorSpace) -> CGImage? {
        let mw = 824
        let mh = 824

        // Locate mask PNG
        guard let validURL = Bundle.main.url(forResource: "alp_mountain_mask", withExtension: "png"),
              let maskImg = NSImage(contentsOf: validURL),
              let maskCg = maskImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        guard let gradData = NSMutableData(length: mw * mh * 4),
              let gradCtx = CGContext(
                data: gradData.mutableBytes,
                width: mw,
                height: mh,
                bitsPerComponent: 8,
                bytesPerRow: mw * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return nil
        }

        gradCtx.draw(maskCg, in: CGRect(x: 0, y: 0, width: mw, height: mh))

        let c1 = RGBAColor(hex: config.startColorHex)?.nsColor ?? NSColor(srgbRed: 0.98, green: 0.38, blue: 0.22, alpha: 1.0)
        let c2 = RGBAColor(hex: config.endColorHex)?.nsColor ?? NSColor(srgbRed: 0.82, green: 0.10, blue: 0.88, alpha: 1.0)
        let sc1 = c1.usingColorSpace(.sRGB) ?? c1
        let sc2 = c2.usingColorSpace(.sRGB) ?? c2

        let r1 = sc1.redComponent, g1 = sc1.greenComponent, b1 = sc1.blueComponent
        let r2 = sc2.redComponent, g2 = sc2.greenComponent, b2 = sc2.blueComponent
        let grain = CGFloat(config.grain)

        let gradPix = gradData.mutableBytes.bindMemory(to: UInt8.self, capacity: mw * mh * 4)

        for y in 0..<mh {
            let ty = CGFloat(y) / CGFloat(mh)
            for x in 0..<mw {
                let idx = (y * mw + x) * 4
                let mAlpha = gradPix[idx + 3]
                if mAlpha > 0 {
                    let tx = CGFloat(x) / CGFloat(mw)
                    var t = (tx + ty) * 0.5
                    t = min(max(t, 0.0), 1.0)

                    var r = r1 * (1.0 - t) + r2 * t
                    var g = g1 * (1.0 - t) + g2 * t
                    var b = b1 * (1.0 - t) + b2 * t

                    if grain > 0.0 {
                        let noise = (CGFloat(arc4random() % 1000) / 1000.0 - 0.5) * grain * 0.35
                        r = min(1.0, max(0.0, r + noise))
                        g = min(1.0, max(0.0, g + noise))
                        b = min(1.0, max(0.0, b + noise))
                    }

                    let aScale = CGFloat(mAlpha) / 255.0
                    gradPix[idx] = UInt8(min(255, max(0, r * 255.0 * aScale)))
                    gradPix[idx + 1] = UInt8(min(255, max(0, g * 255.0 * aScale)))
                    gradPix[idx + 2] = UInt8(min(255, max(0, b * 255.0 * aScale)))
                    gradPix[idx + 3] = mAlpha
                } else {
                    gradPix[idx] = 0
                    gradPix[idx + 1] = 0
                    gradPix[idx + 2] = 0
                    gradPix[idx + 3] = 0
                }
            }
        }

        return gradCtx.makeImage()
    }

    // MARK: - Save and Export

    public static func saveCustomIconToDisk(image: NSImage) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AlpBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("custom_icon.png")

        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("Failed to save custom icon to disk: \(error)")
            return nil
        }
    }

    public static func loadCustomIconFromDisk() -> NSImage? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fileURL = appSupport.appendingPathComponent("AlpBrowser/custom_icon.png")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return NSImage(contentsOf: fileURL)
        }
        return nil
    }

    // MARK: - Apply Icon to Dock and Finder

    public static func applyIcon(image: NSImage) {
        // 1. Immediately apply to the active running Dock process
        NSApp.applicationIconImage = image

        // 2. Persist to Application Support for cold launch restoration
        _ = saveCustomIconToDisk(image: image)

        // 3. Update the Finder icon on the .app bundle
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            NSWorkspace.shared.setIcon(image, forFile: bundlePath, options: [])
        }

        // Try /Applications if installed
        let applicationsPath = "/Applications/Alp Browser.app"
        if FileManager.default.fileExists(atPath: applicationsPath) {
            NSWorkspace.shared.setIcon(image, forFile: applicationsPath, options: [])
        }
    }
}
