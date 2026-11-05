//
//  FaviconCache.swift
//  Alp Browser
//
//  Asynchronous on-device favicon fetcher and disk/memory cache.
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

    /// Hosts being loaded right now, and hosts that already failed this session. Without these, every
    /// view refresh for a not-yet-cached host started another disk read and network request.
    private var inFlight = Set<String>()
    private var failed = Set<String>()

    /// Returns a cached icon immediately, or nil while it loads (disk first, then network) off the main
    /// thread; observers are notified when it arrives.
    public func favicon(for urlString: String) -> NSImage? {
        guard let host = host(from: urlString) else { return nil }
        let key = host as NSString

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        guard !inFlight.contains(host), !failed.contains(host) else { return nil }
        inFlight.insert(host)

        let diskPath = cacheDirectory.appendingPathComponent("\(host).png")
        Task {
            let diskData = await Task.detached(priority: .utility) { try? Data(contentsOf: diskPath) }.value
            if let diskData, let image = NSImage(data: diskData) {
                memoryCache.setObject(image, forKey: key)
                inFlight.remove(host)
                objectWillChange.send()
                return
            }
            await fetchFavicon(forHost: host)
            inFlight.remove(host)
        }
        return nil
    }

    public func fetchFavicon(forHost host: String) async {
        guard let data = await Self.downloadIcon(forHost: host), let image = NSImage(data: data) else {
            // Silently fall back to SF Symbols; don't retry this host until next launch.
            failed.insert(host)
            return
        }
        memoryCache.setObject(image, forKey: host as NSString)
        let diskPath = cacheDirectory.appendingPathComponent("\(host).png")
        Task.detached(priority: .utility) { try? data.write(to: diskPath) }
        objectWillChange.send()
    }

    // MARK: - On-device fetching
    //
    // Icons come from the site itself (its /favicon.ico, else the <link rel="icon"> in its home page),
    // never from a third-party icon service, so visited hosts are not disclosed to anyone but the
    // site being visited. Requests carry no cookies and nothing is stored in the shared URL cache.

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    private static let maxIconBytes = 512 * 1024
    private static let maxPageBytes = 128 * 1024

    /// Only public-looking host names are probed: no bare names, `.local`, or IP literals.
    nonisolated static func isProbeableHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        guard lower.contains("."), !lower.hasSuffix(".local"), !lower.hasSuffix(".internal"),
              !lower.hasSuffix(".localhost"), !lower.contains(":") else { return false }
        let isIPv4 = lower.split(separator: ".").allSatisfy { $0.allSatisfy(\.isNumber) }
        return !isIPv4
    }

    nonisolated private static func downloadIcon(forHost host: String) async -> Data? {
        guard isProbeableHost(host), let home = URL(string: "https://\(host)/") else { return nil }

        if let conventional = URL(string: "/favicon.ico", relativeTo: home)?.absoluteURL,
           let data = await fetchImageData(conventional) {
            return data
        }
        guard let html = await fetch(home, maxBytes: maxPageBytes),
              let page = String(data: html, encoding: .utf8) ?? String(data: html, encoding: .isoLatin1),
              let declared = iconURL(inHTML: page, baseURL: home),
              declared.scheme == "https" else { return nil }
        return await fetchImageData(declared)
    }

    nonisolated private static func fetch(_ url: URL, maxBytes: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(maxBytes - 1)", forHTTPHeaderField: "Range")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return data.count > maxBytes ? data.prefix(maxBytes) : data
    }

    nonisolated private static func fetchImageData(_ url: URL) async -> Data? {
        guard let data = await fetch(url, maxBytes: maxIconBytes), !data.isEmpty,
              NSImage(data: data) != nil else { return nil }
        return data
    }

    /// Finds the best `<link rel="icon">` style reference in a page and resolves it against `baseURL`.
    /// Plain icons win over touch icons; SVG and `data:` references are skipped.
    nonisolated static func iconURL(inHTML html: String, baseURL: URL) -> URL? {
        guard let tagPattern = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        var touchIcon: URL?

        for match in tagPattern.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  let href = attribute("href", in: tag)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty, !href.lowercased().hasPrefix("data:"),
                  let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  resolved.pathExtension.lowercased() != "svg" else { continue }
            let tokens = rel.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if tokens.contains("icon") { return resolved }
            if tokens.contains("apple-touch-icon"), touchIcon == nil { touchIcon = resolved }
        }
        return touchIcon
    }

    nonisolated private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 {
            if let r = Range(m.range(at: group), in: tag) { return String(tag[r]) }
        }
        return nil
    }

    private func host(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
