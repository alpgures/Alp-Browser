//
//  AlpExtensionManager.swift
//  Alp Browser
//
//  Clean-room Web Extensions Manager supporting macOS 15.4+ native WKWebExtensionController
//  with safe fallback on macOS 14.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import WebKit
import SwiftUI
import AppKit

public struct AlpExtensionModel: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String
    public var isEnabled: Bool
    public var directoryURLPath: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        version: String = "1.0",
        description: String = "",
        isEnabled: Bool = true,
        directoryURLPath: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.isEnabled = isEnabled
        self.directoryURLPath = directoryURLPath
    }
}

@MainActor
public final class AlpExtensionManager: ObservableObject {
    public static let shared = AlpExtensionManager()

    @Published public var installedExtensions: [AlpExtensionModel] = []
    @Published public var isExtensionLoading: Bool = false
    @Published public var lastErrorMessage: String?

    private var _extensionController: Any?
    private var activeContexts: [String: Any] = [:]

    @available(macOS 15.4, *)
    public var extensionController: WKWebExtensionController? {
        get { _extensionController as? WKWebExtensionController }
        set { _extensionController = newValue }
    }

    private var extensionsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AlpBrowser/Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var manifestStoreURL: URL {
        extensionsDirectory.appendingPathComponent("installed_extensions.json")
    }

    private init() {
        if #available(macOS 15.4, *) {
            self._extensionController = WKWebExtensionController()
        }
        loadSavedRegistry()
        Task {
            await loadAllInstalledExtensions()
        }
    }

    // MARK: - Registry Persistence

    private func loadSavedRegistry() {
        guard FileManager.default.fileExists(atPath: manifestStoreURL.path),
              let data = try? Data(contentsOf: manifestStoreURL),
              let list = try? JSONDecoder().decode([AlpExtensionModel].self, from: data) else {
            return
        }
        self.installedExtensions = list
    }

    private func saveRegistry() {
        if let data = try? JSONEncoder().encode(installedExtensions) {
            try? data.write(to: manifestStoreURL, options: .atomic)
        }
    }

    // MARK: - Extension Lifecycle

    @available(macOS 15.4, *)
    private func grantAllPermissions(to context: WKWebExtensionContext, for webExt: WKWebExtension) {
        var perms: [WKWebExtension.Permission: Date] = [:]
        for p in webExt.requestedPermissions {
            perms[p] = Date.distantFuture
        }
        context.grantedPermissions = perms

        var patterns: [WKWebExtension.MatchPattern: Date] = [:]
        for pattern in webExt.requestedPermissionMatchPatterns {
            patterns[pattern] = Date.distantFuture
        }
        context.grantedPermissionMatchPatterns = patterns
    }

    public func loadAllInstalledExtensions() async {
        guard #available(macOS 15.4, *), let controller = extensionController else { return }

        for item in installedExtensions where item.isEnabled {
            let dirURL = URL(fileURLWithPath: item.directoryURLPath)
            guard FileManager.default.fileExists(atPath: dirURL.path) else { continue }
            do {
                let webExt = try await WKWebExtension(resourceBaseURL: dirURL)
                let context = WKWebExtensionContext(for: webExt)
                grantAllPermissions(to: context, for: webExt)
                try controller.load(context)
                activeContexts[item.id] = context
            } catch {
                print("Failed to load extension '\(item.name)': \(error)")
            }
        }
    }

    public func installExtensionFromOpenPanel() async {
        let panel = NSOpenPanel()
        panel.title = "Select Unpacked Extension Folder (Containing manifest.json)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else { return }

        let manifestFile = selectedURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestFile.path) else {
            lastErrorMessage = "Selected directory does not contain a valid manifest.json file."
            return
        }

        do {
            try await installExtension(from: selectedURL)
        } catch {
            lastErrorMessage = "Error installing extension: \(error.localizedDescription)"
        }
    }

    public func installExtension(from sourceFolderURL: URL) async throws {
        guard #available(macOS 15.4, *), let controller = extensionController else {
            throw NSError(domain: "AlpExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Extensions require macOS 15.4 or newer."])
        }

        isExtensionLoading = true
        defer { isExtensionLoading = false }

        let extID = UUID().uuidString
        let destinationDir = extensionsDirectory.appendingPathComponent(extID, isDirectory: true)

        try FileManager.default.copyItem(at: sourceFolderURL, to: destinationDir)

        let webExt = try await WKWebExtension(resourceBaseURL: destinationDir)
        let name = webExt.displayName ?? sourceFolderURL.lastPathComponent
        let version = webExt.displayVersion ?? "1.0"
        let description = webExt.displayShortName ?? ""

        let model = AlpExtensionModel(
            id: extID,
            name: name,
            version: version,
            description: description,
            isEnabled: true,
            directoryURLPath: destinationDir.path
        )

        let context = WKWebExtensionContext(for: webExt)
        grantAllPermissions(to: context, for: webExt)
        try controller.load(context)
        activeContexts[extID] = context

        installedExtensions.append(model)
        saveRegistry()
    }

    public func toggleExtension(id: String) async {
        guard #available(macOS 15.4, *), let controller = extensionController else { return }
        guard let idx = installedExtensions.firstIndex(where: { $0.id == id }) else { return }

        let newState = !installedExtensions[idx].isEnabled
        installedExtensions[idx].isEnabled = newState
        saveRegistry()

        if newState {
            // Enable and load
            let dirURL = URL(fileURLWithPath: installedExtensions[idx].directoryURLPath)
            if let webExt = try? await WKWebExtension(resourceBaseURL: dirURL) {
                let context = WKWebExtensionContext(for: webExt)
                grantAllPermissions(to: context, for: webExt)
                try? controller.load(context)
                activeContexts[id] = context
            }
        } else {
            // Unload
            if let context = activeContexts.removeValue(forKey: id) as? WKWebExtensionContext {
                try? controller.unload(context)
            }
        }
    }

    public func removeExtension(id: String) async {
        guard #available(macOS 15.4, *), let controller = extensionController else { return }

        if let context = activeContexts.removeValue(forKey: id) as? WKWebExtensionContext {
            try? controller.unload(context)
        }

        if let idx = installedExtensions.firstIndex(where: { $0.id == id }) {
            let path = installedExtensions[idx].directoryURLPath
            try? FileManager.default.removeItem(atPath: path)
            installedExtensions.remove(at: idx)
            saveRegistry()
        }
    }
}
