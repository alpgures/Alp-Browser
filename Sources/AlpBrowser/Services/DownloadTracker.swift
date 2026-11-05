//
//  DownloadTracker.swift
//  Alp Browser
//
//  Tracks in-flight WKDownloads so the Library can show live progress, and keeps a
//  persistent history of the downloads this browser itself performed. The Library's
//  Downloads and Media lists read only this history, never the ~/Downloads folder.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import WebKit

/// One download made inside this browser.
struct DownloadRecord: Identifiable, Codable, Equatable {
    enum State: String, Codable {
        case completed
        case failed
    }

    let id: UUID
    /// Absolute path of the saved file.
    var filePath: String
    /// Site the download came from (page host, falling back to the request host); nil when unknown.
    var sourceHost: String?
    var date: Date
    var state: State

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var fileName: String { fileURL.lastPathComponent }
}

@MainActor
final class DownloadTracker: ObservableObject {
    static let shared = DownloadTracker()

    struct ActiveDownload: Identifiable, Equatable {
        let id: UUID
        let fileURL: URL
        var sourceHost: String?
        var fraction: Double
        var receivedBytes: Int64
        var totalBytes: Int64
    }

    /// Transfers currently in progress, oldest first.
    @Published private(set) var active: [ActiveDownload] = []
    /// Finished and failed downloads made by this browser, newest first.
    @Published private(set) var records: [DownloadRecord] = []
    /// Bumped whenever a transfer finishes or fails, so views can refresh.
    @Published private(set) var finishedCount: Int = 0

    private static let maxRecords = 500
    private var ids: [ObjectIdentifier: UUID] = [:]
    private var downloads: [UUID: WKDownload] = [:]
    private var observers: [UUID: NSKeyValueObservation] = [:]
    private var sources: [UUID: (path: String, host: String?)] = [:]

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AlpBrowser", isDirectory: true).appendingPathComponent("downloads.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.storeURL),
           let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = decoded.sorted { $0.date > $1.date }
        }
    }

    /// True while at least one transfer is still running; a finished or failed download is not counted.
    var hasActiveDownloads: Bool { !active.isEmpty }

    /// Stops every running transfer. Called when the app quits.
    func cancelAll() {
        let running = Array(downloads.values)
        for download in running { download.cancel { _ in } }
    }

    func begin(_ download: WKDownload, destination: URL) {
        let id = UUID()
        let host = Self.sourceHost(of: download)
        ids[ObjectIdentifier(download)] = id
        downloads[id] = download
        sources[id] = (destination.path, host)
        active.append(ActiveDownload(id: id, fileURL: destination, sourceHost: host, fraction: 0, receivedBytes: 0, totalBytes: 0))

        let progress = download.progress
        observers[id] = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] prog, _ in
            let fraction = prog.fractionCompleted
            let received = prog.completedUnitCount
            let total = prog.totalUnitCount
            Task { @MainActor in
                self?.update(id: id, fraction: fraction, received: received, total: total)
            }
        }
    }

    func end(_ download: WKDownload, failed: Bool = false) {
        guard let id = ids.removeValue(forKey: ObjectIdentifier(download)) else { return }
        observers.removeValue(forKey: id)?.invalidate()
        downloads.removeValue(forKey: id)
        active.removeAll { $0.id == id }
        if let source = sources.removeValue(forKey: id) {
            records.insert(DownloadRecord(id: id, filePath: source.path, sourceHost: source.host,
                                          date: Date(), state: failed ? .failed : .completed), at: 0)
            if records.count > Self.maxRecords { records.removeLast(records.count - Self.maxRecords) }
            persist()
        }
        finishedCount += 1
    }

    /// Removes a record from the history. The file on disk is left alone.
    func remove(_ record: DownloadRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    private func persist() {
        let snapshot = records
        let url = Self.storeURL
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func sourceHost(of download: WKDownload) -> String? {
        let candidates = [download.webView?.url?.host, download.originalRequest?.url?.host]
        for case let host? in candidates where !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return nil
    }

    private func update(id: UUID, fraction: Double, received: Int64, total: Int64) {
        guard let idx = active.firstIndex(where: { $0.id == id }) else { return }
        // Skip sub-percent changes so a fast transfer doesn't re-render the Library constantly.
        guard fraction - active[idx].fraction >= 0.01 || fraction >= 1 else { return }
        active[idx].fraction = max(0, min(1, fraction))
        active[idx].receivedBytes = received
        active[idx].totalBytes = total
    }
}
