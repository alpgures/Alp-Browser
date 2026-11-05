//
//  AlpAssetLoader.swift
//  Alp Browser
//
//  Clean-room procedural asset generator and sound manager.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import AppKit
import CoreGraphics

@MainActor
public final class AlpAssetLoader {
    public static let shared = AlpAssetLoader()

    private var cachedTextures: [String: NSImage] = [:]

    private init() {}

    /// Generates a clean procedural subtle noise/grain texture.
    /// Completely original procedural CoreGraphics generator without any external proprietary assets.
    public func textureImage(named name: String = "grain", size: CGSize = CGSize(width: 128, height: 128)) -> NSImage? {
        if let cached = cachedTextures[name] {
            return cached
        }

        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixelData = [UInt8](repeating: 0, count: width * height)

        var seed: UInt32 = 0x12345678
        for i in 0..<(width * height) {
            seed = (1103515245 &* seed &+ 12345) & 0x7fffffff
            let rand = UInt8((seed >> 16) & 0xFF)
            // subtle grain centered around 128
            let offset = (Int(rand) - 128) / 4
            let value = max(0, min(255, 128 + offset))
            pixelData[i] = UInt8(value)
        }

        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: size)
        cachedTextures[name] = image
        return image
    }

    /// Clean curated color palette swatches for space theme customization.
    public var officialColorSwatches: [(group: String, colors: [RGBAColor])] {
        [
            (
                group: "Pastel",
                colors: [
                    RGBAColor(red: 0.96, green: 0.76, blue: 0.76),
                    RGBAColor(red: 0.98, green: 0.85, blue: 0.72),
                    RGBAColor(red: 0.99, green: 0.94, blue: 0.75),
                    RGBAColor(red: 0.81, green: 0.93, blue: 0.83),
                    RGBAColor(red: 0.76, green: 0.89, blue: 0.96),
                    RGBAColor(red: 0.82, green: 0.82, blue: 0.96),
                    RGBAColor(red: 0.92, green: 0.80, blue: 0.95),
                    RGBAColor(red: 0.96, green: 0.80, blue: 0.87),
                    RGBAColor(red: 0.88, green: 0.88, blue: 0.88)
                ]
            ),
            (
                group: "Vibrant",
                colors: [
                    RGBAColor(red: 0.92, green: 0.34, blue: 0.34),
                    RGBAColor(red: 0.95, green: 0.58, blue: 0.28),
                    RGBAColor(red: 0.96, green: 0.82, blue: 0.26),
                    RGBAColor(red: 0.36, green: 0.76, blue: 0.44),
                    RGBAColor(red: 0.26, green: 0.65, blue: 0.90),
                    RGBAColor(red: 0.45, green: 0.44, blue: 0.88),
                    RGBAColor(red: 0.76, green: 0.38, blue: 0.85),
                    RGBAColor(red: 0.90, green: 0.34, blue: 0.62),
                    RGBAColor(red: 0.32, green: 0.27, blue: 0.37)
                ]
            ),
            (
                group: "Greyscale",
                colors: [
                    RGBAColor(red: 0.95, green: 0.95, blue: 0.95),
                    RGBAColor(red: 0.85, green: 0.85, blue: 0.85),
                    RGBAColor(red: 0.72, green: 0.72, blue: 0.72),
                    RGBAColor(red: 0.58, green: 0.58, blue: 0.58),
                    RGBAColor(red: 0.45, green: 0.45, blue: 0.45),
                    RGBAColor(red: 0.34, green: 0.34, blue: 0.34),
                    RGBAColor(red: 0.24, green: 0.24, blue: 0.24),
                    RGBAColor(red: 0.16, green: 0.16, blue: 0.16),
                    RGBAColor(red: 0.08, green: 0.08, blue: 0.08)
                ]
            )
        ]
    }

    /// Native macOS system sound playback.
    public func playSystemSound(_ soundName: String = "Tink") {
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.volume = 0.45
            sound.play()
        }
    }
}
