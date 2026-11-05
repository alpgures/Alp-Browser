//
//  AlpExtensionManager.swift
//  Alp Browser
//
//  Clean-room Web Extensions Manager supporting macOS 15.4+ native WKWebExtensionController
//  and automatic importing of installed extensions from Arc Browser.
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
    public var iconPath: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        version: String = "1.0",
        description: String = "",
        isEnabled: Bool = true,
        directoryURLPath: String,
        iconPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.isEnabled = isEnabled
        self.directoryURLPath = directoryURLPath
        self.iconPath = iconPath
    }

    public var iconImage: NSImage? {
        if let iconPath = iconPath, FileManager.default.fileExists(atPath: iconPath),
           let img = NSImage(contentsOfFile: iconPath) {
            return img
        }
        return nil
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
        // Automatically import extensions from Arc Browser if none are loaded or missing icons
        importExtensionsFromArc(silent: true)
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

    // MARK: - Automatic Arc Browser Extension Importer

    @discardableResult
    public func importExtensionsFromArc(silent: Bool = false) -> Int {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let arcUserData = home.appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true)
        let candidateDirs = [
            arcUserData.appendingPathComponent("Default/Extensions", isDirectory: true),
            arcUserData.appendingPathComponent("Profile 1/Extensions", isDirectory: true)
        ]

        var importedCount = 0
        let fm = FileManager.default

        for extRoot in candidateDirs {
            guard fm.fileExists(atPath: extRoot.path),
                  let extIDs = try? fm.contentsOfDirectory(atPath: extRoot.path) else {
                continue
            }

            for extID in extIDs.sorted() {
                if extID.hasPrefix(".") || extID == "Temp" { continue }
                // Skip built-in Google Docs Offline internal component unless user wants it
                if extID == "ghbmnnjooekpmoecnnnilnnbdlolhkhi" { continue }

                let extFolder = extRoot.appendingPathComponent(extID, isDirectory: true)
                guard let versions = try? fm.contentsOfDirectory(atPath: extFolder.path)
                    .filter({ !$0.hasPrefix(".") })
                    .sorted(),
                      let latestVer = versions.last else {
                    continue
                }

                let versionDir = extFolder.appendingPathComponent(latestVer, isDirectory: true)
                let manifestURL = versionDir.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let defaultLocale = (json["default_locale"] as? String) ?? "en"
                let rawName = (json["name"] as? String) ?? extID
                let rawDesc = (json["description"] as? String) ?? ""
                let rawVersion = (json["version"] as? String) ?? latestVer

                let resolvedName = Self.resolveLocalizedMessage(rawName, in: versionDir, defaultLocale: defaultLocale)
                let resolvedDesc = Self.resolveLocalizedMessage(rawDesc, in: versionDir, defaultLocale: defaultLocale)
                let resolvedIconPath = Self.resolveBestIconPath(from: json, in: versionDir)

                if let existingIdx = installedExtensions.firstIndex(where: { $0.id == extID || $0.name == resolvedName }) {
                    installedExtensions[existingIdx].name = resolvedName
                    installedExtensions[existingIdx].version = rawVersion
                    installedExtensions[existingIdx].description = resolvedDesc
                    installedExtensions[existingIdx].directoryURLPath = versionDir.path
                    if let icon = resolvedIconPath {
                        installedExtensions[existingIdx].iconPath = icon
                    }
                } else {
                    let model = AlpExtensionModel(
                        id: extID,
                        name: resolvedName,
                        version: rawVersion,
                        description: resolvedDesc,
                        isEnabled: true,
                        directoryURLPath: versionDir.path,
                        iconPath: resolvedIconPath
                    )
                    installedExtensions.append(model)
                    importedCount += 1
                }
            }
        }

        if importedCount > 0 || !installedExtensions.isEmpty {
            saveRegistry()
        }
        return importedCount
    }

    private static func resolveLocalizedMessage(_ raw: String, in versionDir: URL, defaultLocale: String) -> String {
        guard raw.hasPrefix("__MSG_"), raw.hasSuffix("__"), raw.count > 8 else {
            return raw
        }
        let key = String(raw.dropFirst(6).dropLast(2))
        let localesDir = versionDir.appendingPathComponent("_locales", isDirectory: true)
        var candidateLocales = ["en", "en_US", "en_GB", defaultLocale]
        if let allLocales = try? FileManager.default.contentsOfDirectory(atPath: localesDir.path) {
            for loc in allLocales where !candidateLocales.contains(loc) {
                candidateLocales.append(loc)
            }
        }

        for loc in candidateLocales {
            let msgFile = localesDir.appendingPathComponent(loc).appendingPathComponent("messages.json")
            guard let data = try? Data(contentsOf: msgFile),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let entry = dict[key] as? [String: Any], let msg = entry["message"] as? String {
                return msg
            }
            if let match = dict.first(where: { $0.key.lowercased() == key.lowercased() }),
               let entry = match.value as? [String: Any],
               let msg = entry["message"] as? String {
                return msg
            }
        }
        return raw
    }

    private static func resolveBestIconPath(from manifest: [String: Any], in versionDir: URL) -> String? {
        var iconDict: [String: Any] = [:]
        if let icons = manifest["icons"] as? [String: Any] {
            iconDict = icons
        } else if let action = manifest["action"] as? [String: Any],
                  let defIcon = action["default_icon"] as? [String: Any] {
            iconDict = defIcon
        } else if let browserAction = manifest["browser_action"] as? [String: Any],
                  let defIcon = browserAction["default_icon"] as? [String: Any] {
            iconDict = defIcon
        }

        for sizeKey in ["128", "64", "48", "32", "256", "16"] {
            if let relPath = iconDict[sizeKey] as? String {
                let cleanRel = relPath.hasPrefix("/") ? String(relPath.dropFirst()) : relPath
                let fullURL = versionDir.appendingPathComponent(cleanRel)
                if FileManager.default.fileExists(atPath: fullURL.path) {
                    return fullURL.path
                }
            }
        }
        for (_, val) in iconDict {
            if let relPath = val as? String {
                let cleanRel = relPath.hasPrefix("/") ? String(relPath.dropFirst()) : relPath
                let fullURL = versionDir.appendingPathComponent(cleanRel)
                if FileManager.default.fileExists(atPath: fullURL.path) {
                    return fullURL.path
                }
            }
        }
        return nil
    }

    // MARK: - Extension Lifecycle

    /// Least privilege: an extension is granted only what its manifest declares as required
    /// (`permissions` and `host_permissions`). Optional permissions and optional host patterns are
    /// never granted here, and anything not declared stays ungranted.
    @available(macOS 15.4, *)
    private func grantDeclaredPermissions(to context: WKWebExtensionContext, for webExt: WKWebExtension) {
        let declared = webExt.requestedPermissions.subtracting(webExt.optionalPermissions)
        context.grantedPermissions = Dictionary(uniqueKeysWithValues: declared.map { ($0, Date.distantFuture) })

        let declaredPatterns = webExt.requestedPermissionMatchPatterns.subtracting(webExt.optionalPermissionMatchPatterns)
        context.grantedPermissionMatchPatterns = Dictionary(uniqueKeysWithValues: declaredPatterns.map { ($0, Date.distantFuture) })
    }

    public func loadAllInstalledExtensions() async {
        guard #available(macOS 15.4, *), let controller = extensionController else { return }

        for item in installedExtensions where item.isEnabled {
            let dirURL = URL(fileURLWithPath: item.directoryURLPath)
            guard FileManager.default.fileExists(atPath: dirURL.path) else { continue }
            do {
                let webExt = try await WKWebExtension(resourceBaseURL: dirURL)
                let context = WKWebExtensionContext(for: webExt)
                grantDeclaredPermissions(to: context, for: webExt)
                try controller.load(context)
                activeContexts[item.id] = context
            } catch {
                // Non-fatal if a Chrome-specific background worker script isn't supported in WebKit yet
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
        isExtensionLoading = true
        defer { isExtensionLoading = false }

        let extID = UUID().uuidString
        let destinationDir = extensionsDirectory.appendingPathComponent(extID, isDirectory: true)
        try FileManager.default.copyItem(at: sourceFolderURL, to: destinationDir)

        var name = sourceFolderURL.lastPathComponent
        var version = "1.0"
        var description = ""
        var iconPath: String? = nil

        let manifestURL = destinationDir.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let defaultLocale = (json["default_locale"] as? String) ?? "en"
            if let rawName = json["name"] as? String {
                name = Self.resolveLocalizedMessage(rawName, in: destinationDir, defaultLocale: defaultLocale)
            }
            if let rawDesc = json["description"] as? String {
                description = Self.resolveLocalizedMessage(rawDesc, in: destinationDir, defaultLocale: defaultLocale)
            }
            if let rawVer = json["version"] as? String {
                version = rawVer
            }
            iconPath = Self.resolveBestIconPath(from: json, in: destinationDir)
        }

        if #available(macOS 15.4, *), let controller = extensionController,
           let webExt = try? await WKWebExtension(resourceBaseURL: destinationDir) {
            if let displayName = webExt.displayName, !displayName.isEmpty { name = displayName }
            if let displayVer = webExt.displayVersion, !displayVer.isEmpty { version = displayVer }
            let context = WKWebExtensionContext(for: webExt)
            grantDeclaredPermissions(to: context, for: webExt)
            try? controller.load(context)
            activeContexts[extID] = context
        }

        let model = AlpExtensionModel(
            id: extID,
            name: name,
            version: version,
            description: description,
            isEnabled: true,
            directoryURLPath: destinationDir.path,
            iconPath: iconPath
        )

        installedExtensions.append(model)
        saveRegistry()
    }

    // MARK: - Chrome Web Store Install

    /// Accepts a Web Store detail link or a bare 32-letter extension ID, downloads the
    /// packed extension, verifies its CRX signature, unpacks it and installs it like an unpacked folder.
    @discardableResult
    public func installFromWebStore(_ input: String) async -> Bool {
        guard let range = input.range(of: "[a-p]{32}", options: .regularExpression) else {
            lastErrorMessage = "Enter a Chrome Web Store link or a 32-letter extension ID."
            return false
        }
        let extensionID = String(input[range])
        let query = "id%3D\(extensionID)%26installsource%3Dondemand%26uc"
        guard let url = URL(string: "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=120.0&acceptformat=crx2,crx3&x=\(query)") else { return false }

        isExtensionLoading = true
        defer { isExtensionLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                lastErrorMessage = "That extension could not be downloaded."
                return false
            }
            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("alp-crx-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDir) }

            let unpacked = workDir.appendingPathComponent("unpacked", isDirectory: true)
            // Verify the CRX signature (and that the signing key matches the requested ID) before
            // anything is scanned, unzipped or installed. A failure throws a CRXVerificationError.
            // Order: verify signature, scan zip entries for path escapes, then unzip.
            try await Task.detached(priority: .userInitiated) {
                let package = try CRXVerifier.verify(data, expectedExtensionID: extensionID)
                try Self.unzipPayload(package.zipPayload, into: unpacked, workDir: workDir)
            }.value
            try await installExtension(from: unpacked)
            return true
        } catch {
            lastErrorMessage = "Error installing extension: \(error.localizedDescription)"
            return false
        }
    }

    /// Unzips an already-verified CRX payload with the system `ditto`, after refusing any archive
    /// whose entries could land outside `destination` (absolute paths, `..`, links).
    nonisolated private static func unzipPayload(_ zip: Data, into destination: URL, workDir: URL) throws {
        try ZipArchiveScanner.scan(zip)

        let zipURL = workDir.appendingPathComponent("payload.zip")
        try zip.write(to: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: destination.appendingPathComponent("manifest.json").path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Belt and braces: nothing may have been unpacked as a link, and nothing may sit next to
        // the destination (workDir should hold only payload.zip and the unpacked folder).
        try ZipArchiveScanner.verifyExtractedTree(at: destination)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: workDir.path)
        guard Set(siblings) == [zipURL.lastPathComponent, destination.lastPathComponent] else {
            throw ZipScanError.unsafeEntry(name: "(archive)", reason: "wrote files outside the destination")
        }
    }

    public func toggleExtension(id: String) async {
        guard let idx = installedExtensions.firstIndex(where: { $0.id == id }) else { return }

        let newState = !installedExtensions[idx].isEnabled
        installedExtensions[idx].isEnabled = newState
        saveRegistry()

        guard #available(macOS 15.4, *), let controller = extensionController else { return }
        if newState {
            let dirURL = URL(fileURLWithPath: installedExtensions[idx].directoryURLPath)
            if let webExt = try? await WKWebExtension(resourceBaseURL: dirURL) {
                let context = WKWebExtensionContext(for: webExt)
                grantDeclaredPermissions(to: context, for: webExt)
                try? controller.load(context)
                activeContexts[id] = context
            }
        } else {
            if let context = activeContexts.removeValue(forKey: id) as? WKWebExtensionContext {
                try? controller.unload(context)
            }
        }
    }

    public func removeExtension(id: String) async {
        if #available(macOS 15.4, *), let controller = extensionController,
           let context = activeContexts.removeValue(forKey: id) as? WKWebExtensionContext {
            try? controller.unload(context)
        }

        if let idx = installedExtensions.firstIndex(where: { $0.id == id }) {
            let path = installedExtensions[idx].directoryURLPath
            if path.contains("AlpBrowser/Extensions") {
                try? FileManager.default.removeItem(atPath: path)
            }
            installedExtensions.remove(at: idx)
            saveRegistry()
        }
    }
}
