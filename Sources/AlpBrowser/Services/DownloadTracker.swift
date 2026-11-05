//
//  DownloadTracker.swift
//  Alp Browser
//
//  Tracks in-flight WKDownloads so the Library can show live progress and
//  refresh its list when a transfer finishes.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import WebKit

@MainActor
final class DownloadTracker: ObservableObject {
    static let shared = DownloadTracker()

    struct ActiveDownload: Identifiable, Equatable {
        let id: UUID
        let fileURL: URL
        var fraction: Double
        var receivedBytes: Int64
        var totalBytes: Int64
    }

    /// Transfers currently in progress, oldest first.
    @Published private(set) var active: [ActiveDownload] = []
    /// Bumped whenever a transfer finishes or fails, so views can reload their file lists.
    @Published private(set) var finishedCount: Int = 0

    private var ids: [ObjectIdentifier: UUID] = [:]
    private var observers: [UUID: NSKeyValueObservation] = [:]

    private init() {}

    func begin(_ download: WKDownload, destination: URL) {
        let id = UUID()
        ids[ObjectIdentifier(download)] = id
        active.append(ActiveDownload(id: id, fileURL: destination, fraction: 0, receivedBytes: 0, totalBytes: 0))

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

    func end(_ download: WKDownload) {
        guard let id = ids.removeValue(forKey: ObjectIdentifier(download)) else { return }
        observers.removeValue(forKey: id)?.invalidate()
        active.removeAll { $0.id == id }
        finishedCount += 1
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
