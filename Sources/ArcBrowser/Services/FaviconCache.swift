import Foundation
import AppKit
import SwiftUI

@MainActor
public final class FaviconCache {
    public static let shared = FaviconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlightCallbacks: [String: [(NSImage?) -> Void]] = [:]

    private init() {
        cache.countLimit = 500
    }

    public func cachedImage(for url: URL?) -> NSImage? {
        guard let url = url else { return nil }
        return cache.object(forKey: url.absoluteString as NSString)
    }

    public func loadImage(for url: URL?, completion: @escaping (NSImage?) -> Void) {
        guard let url = url else {
            completion(nil)
            return
        }
        let key = url.absoluteString
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        if inFlightCallbacks[key] != nil {
            inFlightCallbacks[key]?.append(completion)
            return
        }
        inFlightCallbacks[key] = [completion]

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let decoded: NSImage? = (data != nil) ? NSImage(data: data!) : nil
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let decoded = decoded {
                    self.cache.setObject(decoded, forKey: key as NSString)
                }
                let callbacks = self.inFlightCallbacks.removeValue(forKey: key) ?? []
                for cb in callbacks {
                    cb(decoded)
                }
            }
        }.resume()
    }
}
