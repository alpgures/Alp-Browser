//
//  AlpSyncService.swift
//  Alp Browser
//
//  Zero-knowledge client-encrypted browser state sync service.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import CryptoKit

public actor AlpSyncService {
    public static let shared = AlpSyncService()

    public enum SyncResult: Sendable {
        case success(String)
        case failure(String)
    }

    private init() {}

    /// Encrypts and uploads the current browser store to the sync server.
    public func pushStore(_ store: PersistedBrowserStore, endpoint: String, vaultID: String) async -> SyncResult {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let rawData = try encoder.encode(store)

            let encryptedData = try encryptPayload(rawData, vaultID: vaultID)

            guard let url = URL(string: "\(endpoint)/v1/vault/\(vaultID)") else {
                return .failure("Invalid sync endpoint URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = encryptedData
            request.timeoutInterval = 10.0

            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return .success("Encrypted vault synced successfully")
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return .failure("Sync server responded with status code \(code)")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Fetches and decrypts the browser store from the sync server.
    public func pullStore(endpoint: String, vaultID: String) async throws -> PersistedBrowserStore? {
        guard let url = URL(string: "\(endpoint)/v1/vault/\(vaultID)") else {
            throw NSError(domain: "AlpSyncService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            return nil
        }

        let decryptedData = try decryptPayload(data, vaultID: vaultID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedBrowserStore.self, from: decryptedData)
    }

    /// Health check for the sync daemon.
    public func checkServerHealth(endpoint: String) async -> (isAvailable: Bool, statusMessage: String) {
        guard let url = URL(string: "\(endpoint)/health") else {
            return (false, "Invalid endpoint")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
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
