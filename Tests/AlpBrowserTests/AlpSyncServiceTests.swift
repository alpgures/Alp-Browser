//
//  AlpSyncServiceTests.swift
//  Alp Browser
//
//  Pure checks for the sync service's validation and error messages (no network, no disk).
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import XCTest
@testable import AlpBrowser

final class AlpSyncServiceTests: XCTestCase {
    func testVaultIDsMatchTheDaemonRuleAndCannotEscapeAFolder() {
        XCTAssertTrue(AlpSyncService.isValidVaultID("primary"))
        XCTAssertTrue(AlpSyncService.isValidVaultID("My-Vault_2"))
        XCTAssertTrue(AlpSyncService.isValidVaultID(String(repeating: "a", count: 128)))
        XCTAssertFalse(AlpSyncService.isValidVaultID(""))
        XCTAssertFalse(AlpSyncService.isValidVaultID(String(repeating: "a", count: 129)))
        XCTAssertFalse(AlpSyncService.isValidVaultID("../../etc/passwd"))
        XCTAssertFalse(AlpSyncService.isValidVaultID("a/b"))
        XCTAssertFalse(AlpSyncService.isValidVaultID(".."))
        XCTAssertFalse(AlpSyncService.isValidVaultID("has space"))
        XCTAssertFalse(AlpSyncService.isValidVaultID("vault?x=1"))
    }

    func testEndpointCleaningAcceptsOnlyHTTPWithAHost() {
        XCTAssertEqual(AlpSyncService.cleanedEndpoint(" http://127.0.0.1:8788/ "), "http://127.0.0.1:8788")
        XCTAssertEqual(AlpSyncService.cleanedEndpoint("https://sync.example.com//"), "https://sync.example.com")
        XCTAssertNil(AlpSyncService.cleanedEndpoint(""))
        XCTAssertNil(AlpSyncService.cleanedEndpoint("file:///etc/passwd"))
        XCTAssertNil(AlpSyncService.cleanedEndpoint("ftp://example.com"))
        XCTAssertNil(AlpSyncService.cleanedEndpoint("http://"))
        XCTAssertNil(AlpSyncService.cleanedEndpoint("not a url"))
    }

    func testLocalEndpointDetection() {
        XCTAssertTrue(AlpSyncService.isLocalEndpoint("http://127.0.0.1:8788"))
        XCTAssertTrue(AlpSyncService.isLocalEndpoint("http://localhost:8788"))
        XCTAssertFalse(AlpSyncService.isLocalEndpoint("https://sync.example.com"))
        XCTAssertFalse(AlpSyncService.isLocalEndpoint("https://127.0.0.1.example.com"))
    }

    func testDigestIsStableHexAndSensitiveToChanges() {
        let a = AlpSyncService.digest(of: Data([1, 2, 3]))
        XCTAssertEqual(a, AlpSyncService.digest(of: Data([1, 2, 3])))
        XCTAssertNotEqual(a, AlpSyncService.digest(of: Data([1, 2, 4])))
        XCTAssertEqual(a.count, 64)
    }

    func testNetworkErrorsBecomePlainMessages() {
        XCTAssertEqual(AlpSyncService.syncError(from: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(AlpSyncService.syncError(from: URLError(.cannotConnectToHost)), .serverUnreachable)
        XCTAssertEqual(AlpSyncService.syncError(from: URLError(.timedOut)), .serverUnreachable)
        XCTAssertEqual(AlpSyncService.syncError(from: AlpSyncError.vaultDamaged), .vaultDamaged)
        for error in [AlpSyncError.offline, .serverUnreachable, .invalidEndpoint, .invalidVaultID, .nothingToSync,
                      .tooLarge(bytes: 20_000_000), .serverRejected(status: 500), .serverRejected(status: 413),
                      .remoteTooLarge, .vaultDamaged, .localBackupFailed, .emptyVault] {
            let text = error.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("Error Domain"), "no raw system error text: \(text)")
        }
        XCTAssertTrue(AlpSyncError.tooLarge(bytes: 20_000_000).errorDescription?.contains("still saved on this Mac") == true)
    }

    func testPushRefusesBadSettingsBeforeAnyNetworkOrDiskWork() async {
        let store = PersistedBrowserStore(spaces: [AlpSpace(title: "Personal")])
        let badID = await AlpSyncService.shared.pushStore(store, endpoint: "http://127.0.0.1:1", vaultID: "../x")
        if case .failure(let message) = badID { XCTAssertTrue(message.contains("vault name")) } else { XCTFail("expected failure") }
        let badURL = await AlpSyncService.shared.pushStore(store, endpoint: "nonsense", vaultID: "primary")
        if case .failure(let message) = badURL { XCTAssertTrue(message.contains("address")) } else { XCTFail("expected failure") }
        let empty = await AlpSyncService.shared.pushStore(PersistedBrowserStore(), endpoint: "http://127.0.0.1:1", vaultID: "primary")
        if case .failure(let message) = empty { XCTAssertTrue(message.contains("nothing to back up")) } else { XCTFail("expected failure") }
    }
}
