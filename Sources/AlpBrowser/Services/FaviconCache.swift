//
//  FaviconCache.swift
//  Alp Browser
//
//  Asynchronous favicon fetcher and disk/memory cache.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import AppKit

@MainActor
public final class FaviconCache: ObservableObject {
    public static let shared = FaviconCache()

    private var memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        memoryCache.countLimit = 250
        let baseDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = baseDir.appendingPathComponent("com.alpgures.alpbrowser/Favicons", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func favicon(for urlString: String) -> NSImage? {
        guard let host = host(from: urlString) else { return nil }
        let key = host as NSString

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let diskPath = cacheDirectory.appendingPathComponent("\(host).png")
        if let diskData = try? Data(contentsOf: diskPath), let image = NSImage(data: diskData) {
            memoryCache.setObject(image, forKey: key)
            return image
        }

        // Fetch asynchronously if not cached
        Task {
            await fetchFavicon(forHost: host)
        }
        return nil
    }

    public func fetchFavicon(forHost host: String) async {
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = NSImage(data: data) else {
                return
            }
            let key = host as NSString
            memoryCache.setObject(image, forKey: key)
            let diskPath = cacheDirectory.appendingPathComponent("\(host).png")
            try? data.write(to: diskPath)
            objectWillChange.send()
        } catch {
            // Silently fall back to SF Symbols
        }
    }

    private func host(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
