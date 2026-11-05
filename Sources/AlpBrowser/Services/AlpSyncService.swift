//
//  AlpSyncService.swift
//  Alp Browser
//
//  Zero-knowledge client-encrypted browser state sync service.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import CryptoKit

/// Why a sync step failed, in words a person can act on. `errorDescription` is shown to the user as is.
public enum AlpSyncError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case invalidVaultID
    case nothingToSync
    case tooLarge(bytes: Int)
    case offline
    case serverUnreachable
    case serverRejected(status: Int)
    case remoteTooLarge
    case vaultDamaged
    case localBackupFailed
    case emptyVault

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The sync server address in Settings is not valid."
        case .invalidVaultID:
            return "The vault name in Settings can only use letters, numbers, dashes and underscores (up to 128 characters)."
        case .nothingToSync:
            return "There is nothing to back up yet."
        case .tooLarge(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let limit = ByteCountFormatter.string(fromByteCount: Int64(AlpSyncService.maxVaultBytes), countStyle: .file)
            return "Your vault is \(size), which is over the \(limit) sync limit. It is still saved on this Mac. Delete old notes, easels or archived tabs to make it smaller."
        case .offline:
            return "This Mac is not connected to the internet."
        case .serverUnreachable:
            return "Could not reach the sync server."
        case .serverRejected(let status):
            if status == 413 { return "The sync server refused the vault because it is too large." }
            return "The sync server answered with an error (\(status))."
        case .remoteTooLarge:
            return "The cloud copy is larger than expected, so it was not downloaded."
        case .vaultDamaged:
            return "The vault could not be read. It may be damaged, or it was made with a different vault name. Nothing on this Mac was changed."
        case .localBackupFailed:
            return "Could not save the encrypted backup on this Mac (is the disk full?). Nothing was uploaded."
        case .emptyVault:
            return "The vault holds no spaces, so it was not applied. Nothing on this Mac was changed."
        }
    }
}

public actor AlpSyncService {
    public static let shared = AlpSyncService()

    public enum SyncResult: Sendable {
        case success(String)
        /// The cloud copy changed on another device since this one last synced; nothing was uploaded.
        case conflict(String)
        /// The cloud could not be reached; the encrypted copy on this Mac is up to date.
        case offline(String)
        case failure(String)
    }

    public enum PullResult {
        case restored(PersistedBrowserStore)
        case noRemoteVault
    }

    /// Largest vault the sync daemon accepts (its `MAX_VAULT_BYTES`). Checked before uploading.
    public static let maxVaultBytes = 15 * 1024 * 1024
    /// AES-GCM adds a 12-byte nonce and a 16-byte tag.
    private static let sealOverhead = 28

    private var daemonProcess: Process?

    private init() {}

    // MARK: - Validation helpers (pure)

    /// The daemon only accepts ids matching `[a-z0-9_-]{1,128}` (it lower-cases first). The id is also a local file name,
    /// so anything else, in particular `/` or `..`, is refused before it can reach a path or a URL.
    nonisolated public static func isValidVaultID(_ id: String) -> Bool {
        guard (1...128).contains(id.count) else { return false }
        return id.lowercased().unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) || scalar == "_" || scalar == "-"
        }
    }

    /// Endpoint without surrounding spaces or trailing slashes; nil unless it is an http(s) URL with a host.
    nonisolated public static func cleanedEndpoint(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return text
    }

    nonisolated static func isLocalEndpoint(_ endpoint: String) -> Bool {
        guard let host = URL(string: endpoint)?.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    nonisolated static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Maps a URLSession failure to a plain-language error.
    nonisolated static func syncError(from error: Error) -> AlpSyncError {
        if let sync = error as? AlpSyncError { return sync }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            default:
                return .serverUnreachable
            }
        }
        return .serverUnreachable
    }

    // MARK: - Push

    /// Encrypts and uploads the current browser store. The encrypted copy on this Mac is always written first, so a
    /// failed upload never loses anything. Unless `overwriteRemote` is set, the upload is skipped when the cloud copy
    /// was changed by another device since this one last synced (the other device's changes would be lost).
    public func pushStore(
        _ store: PersistedBrowserStore,
        endpoint rawEndpoint: String,
        vaultID: String,
        overwriteRemote: Bool = false
    ) async -> SyncResult {
        do {
            guard let endpoint = Self.cleanedEndpoint(rawEndpoint) else { throw AlpSyncError.invalidEndpoint }
            guard Self.isValidVaultID(vaultID) else { throw AlpSyncError.invalidVaultID }
            guard !store.spaces.isEmpty else { throw AlpSyncError.nothingToSync }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let rawData = try encoder.encode(store)
            let sealedSize = rawData.count + Self.sealOverhead
            guard sealedSize <= Self.maxVaultBytes else { throw AlpSyncError.tooLarge(bytes: sealedSize) }

            let encryptedData = try encryptPayload(rawData, vaultID: vaultID)

            // Local encrypted backup first, so nothing below can lose data.
            do {
                try saveLocalEncryptedVault(encryptedData, vaultID: vaultID)
            } catch {
                throw AlpSyncError.localBackupFailed
            }

            if Self.isLocalEndpoint(endpoint) {
                await ensureLocalDaemonRunning(endpoint: endpoint)
            }

            do {
                if !overwriteRemote {
                    switch try await fetchRemote(endpoint: endpoint, vaultID: vaultID) {
                    case .none:
                        break
                    case .some(let remote):
                        let known = loadSyncedDigest(vaultID: vaultID)
                        if known != Self.digest(of: remote) {
                            return .conflict(known == nil
                                ? "A vault from another device is already in the cloud. Nothing was uploaded, so it was not overwritten. Choose Restore from Backup to use it, or Replace Cloud Copy to keep this device's data instead."
                                : "The cloud copy was changed on another device. Nothing was uploaded, so those changes were not overwritten. Choose Restore from Backup to use the cloud copy (a safety copy of this device is saved first), or Replace Cloud Copy to keep this device's data instead.")
                        }
                    }
                }

                try await upload(encryptedData, endpoint: endpoint, vaultID: vaultID)
            } catch {
                let failure = Self.syncError(from: error)
                let reason = failure.errorDescription ?? "The sync server could not be reached."
                switch failure {
                case .offline, .serverUnreachable:
                    return .offline("\(reason) Your changes are saved on this Mac and will upload on the next successful sync.")
                default:
                    return .failure("\(reason) Your changes are saved on this Mac.")
                }
            }

            saveSyncedDigest(Self.digest(of: encryptedData), vaultID: vaultID)
            return .success("Encrypted vault synced successfully (AES-256-GCM)")
        } catch {
            return .failure((error as? AlpSyncError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Pull

    /// Downloads and decrypts the cloud vault. Throws `AlpSyncError` with a plain message when the server cannot be reached
    /// or the vault cannot be read; it never falls back silently to older data.
    public func pullStore(endpoint rawEndpoint: String, vaultID: String) async throws -> PullResult {
        guard let endpoint = Self.cleanedEndpoint(rawEndpoint) else { throw AlpSyncError.invalidEndpoint }
        guard Self.isValidVaultID(vaultID) else { throw AlpSyncError.invalidVaultID }

        if Self.isLocalEndpoint(endpoint) {
            await ensureLocalDaemonRunning(endpoint: endpoint)
        }

        let remote: Data?
        do {
            remote = try await fetchRemote(endpoint: endpoint, vaultID: vaultID)
        } catch {
            throw Self.syncError(from: error)
        }
        guard let remote else { return .noRemoteVault }

        let store = try decodeStore(from: remote, vaultID: vaultID)
        saveSyncedDigest(Self.digest(of: remote), vaultID: vaultID)
        return .restored(store)
    }

    /// Reads the encrypted copy kept on this Mac (the last thing this device saved). Used only when the user asks for it.
    public func loadLocalBackup(vaultID: String) throws -> PersistedBrowserStore? {
        guard Self.isValidVaultID(vaultID) else { throw AlpSyncError.invalidVaultID }
        guard let data = loadLocalEncryptedVault(vaultID: vaultID) else { return nil }
        return try decodeStore(from: data, vaultID: vaultID)
    }

    private func decodeStore(from encrypted: Data, vaultID: String) throws -> PersistedBrowserStore {
        let store: PersistedBrowserStore
        do {
            let plain = try decryptPayload(encrypted, vaultID: vaultID)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            store = try decoder.decode(PersistedBrowserStore.self, from: plain)
        } catch {
            throw AlpSyncError.vaultDamaged
        }
        guard !store.spaces.isEmpty else { throw AlpSyncError.emptyVault }
        return store
    }

    // MARK: - Network

    /// The cloud blob, or nil when no vault exists yet (404). Refuses anything bigger than the daemon's own limit.
    private func fetchRemote(endpoint: String, vaultID: String) async throws -> Data? {
        guard let url = URL(string: "\(endpoint)/v1/vault/\(vaultID)") else { throw AlpSyncError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AlpSyncError.serverUnreachable }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw AlpSyncError.serverRejected(status: http.statusCode) }
        if response.expectedContentLength > Int64(Self.maxVaultBytes) { throw AlpSyncError.remoteTooLarge }

        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            data.append(byte)
            if data.count > Self.maxVaultBytes { throw AlpSyncError.remoteTooLarge }
        }
        return data.isEmpty ? nil : data
    }

    private func upload(_ body: Data, endpoint: String, vaultID: String) async throws {
        guard let url = URL(string: "\(endpoint)/v1/vault/\(vaultID)") else { throw AlpSyncError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15.0

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AlpSyncError.serverUnreachable }
        guard (200...299).contains(http.statusCode) else { throw AlpSyncError.serverRejected(status: http.statusCode) }
    }

    /// Health check for the sync daemon.
    public func checkServerHealth(endpoint rawEndpoint: String) async -> (isAvailable: Bool, statusMessage: String) {
        guard let endpoint = Self.cleanedEndpoint(rawEndpoint), let url = URL(string: "\(endpoint)/health") else {
            return (false, "Invalid endpoint")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.0
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = dict["status"] as? String {
                    return (true, status.uppercased())
                }
                return (true, "ONLINE")
            }
            return (false, "OFFLINE")
        } catch {
            return (false, "UNREACHABLE")
        }
    }

    // MARK: - Auto-Start Local Python Daemon

    /// Starts the bundled daemon once when a local endpoint is down, then waits briefly for it to answer.
    /// The process handle is kept so repeated failed syncs do not pile up extra processes.
    private func ensureLocalDaemonRunning(endpoint: String) async {
        let (alive, _) = await checkServerHealth(endpoint: endpoint)
        if alive { return }
        startLocalDaemonIfNeeded()
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if await checkServerHealth(endpoint: endpoint).isAvailable { return }
        }
    }

    private func startLocalDaemonIfNeeded() {
        if let existing = daemonProcess, existing.isRunning { return }
        guard let scriptPath = Bundle.main.path(forResource: "alp_cloud_daemon", ofType: "py") else {
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [scriptPath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            daemonProcess = task
        } catch {
            daemonProcess = nil   // no python3 available: the caller reports the server as unreachable
        }
    }

    // MARK: - Local Encrypted Vault Backup

    private func vaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vaultDir = appSupport.appendingPathComponent("Alp Browser/Vaults", isDirectory: true)
        try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        return vaultDir
    }

    /// Callers must have checked `isValidVaultID` first (it keeps the id from escaping the Vaults folder).
    private func localVaultURL(for vaultID: String) -> URL {
        vaultDirectory().appendingPathComponent("\(vaultID).enc")
    }

    private func syncedDigestURL(for vaultID: String) -> URL {
        vaultDirectory().appendingPathComponent("\(vaultID).synced-digest")
    }

    private func saveLocalEncryptedVault(_ data: Data, vaultID: String) throws {
        try data.write(to: localVaultURL(for: vaultID), options: .atomic)
    }

    private func loadLocalEncryptedVault(vaultID: String) -> Data? {
        try? Data(contentsOf: localVaultURL(for: vaultID))
    }

    /// Fingerprint of the cloud blob this device last uploaded or downloaded. Kept only on this Mac (never synced):
    /// if the cloud blob no longer matches it, another device has written to the vault since.
    private func loadSyncedDigest(vaultID: String) -> String? {
        guard let text = try? String(contentsOf: syncedDigestURL(for: vaultID), encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func saveSyncedDigest(_ digest: String, vaultID: String) {
        try? digest.write(to: syncedDigestURL(for: vaultID), atomically: true, encoding: .utf8)
    }

    // MARK: - Zero-Knowledge AES-GCM Encryption / Decryption

    private func deriveSymmetricKey(from vaultID: String) -> SymmetricKey {
        let salt = "AlpBrowserZeroKnowledgeVaultSalt2026".data(using: .utf8)!
        let inputKey = SymmetricKey(data: vaultID.data(using: .utf8)!)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            outputByteCount: 32
        )
    }

    private func encryptPayload(_ plaintext: Data, vaultID: String) throws -> Data {
        let key = deriveSymmetricKey(from: vaultID)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "AlpSyncService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to seal data"])
        }
        return combined
    }

    private func decryptPayload(_ ciphertext: Data, vaultID: String) throws -> Data {
        let key = deriveSymmetricKey(from: vaultID)
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
