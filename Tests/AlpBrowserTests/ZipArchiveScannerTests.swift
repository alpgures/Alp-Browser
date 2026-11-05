import XCTest
@testable import AlpBrowser

/// Builds minimal "stored" zips in memory (CRC left at 0: the scanner never reads file data).
private struct ZipBuilder {
    struct Item {
        var name: String
        var data: Data = Data()
        var unixMode: UInt32? = nil        // st_mode, stored in the high 16 bits of the external attributes
        var flags: UInt16 = 0
        var localName: String? = nil       // overrides the name in the local header
    }

    static func build(_ items: [Item], comment: Data = Data()) -> Data {
        var out = Data()
        var central = Data()
        for item in items {
            let offset = UInt32(out.count)
            let nameBytes = Data(item.name.utf8)
            let localNameBytes = Data((item.localName ?? item.name).utf8)

            out.append(le32(0x04034b50))
            out.append(le16(20)); out.append(le16(item.flags)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0))
            out.append(le32(0))
            out.append(le32(UInt32(item.data.count))); out.append(le32(UInt32(item.data.count)))
            out.append(le16(UInt16(localNameBytes.count))); out.append(le16(0))
            out.append(localNameBytes)
            out.append(item.data)

            let madeBy: UInt16 = item.unixMode == nil ? 20 : (3 << 8) | 20
            central.append(le32(0x02014b50))
            central.append(le16(madeBy)); central.append(le16(20))
            central.append(le16(item.flags)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0))
            central.append(le32(0))
            central.append(le32(UInt32(item.data.count))); central.append(le32(UInt32(item.data.count)))
            central.append(le16(UInt16(nameBytes.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0))
            central.append(le32((item.unixMode ?? 0) << 16))
            central.append(le32(offset))
            central.append(nameBytes)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50))
        out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(items.count))); out.append(le16(UInt16(items.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(cdOffset))
        out.append(le16(UInt16(comment.count)))
        out.append(comment)
        return out
    }

    static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}

final class ZipArchiveScannerTests: XCTestCase {
    private func assertRefused(_ items: [ZipBuilder.Item], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ZipArchiveScanner.scan(ZipBuilder.build(items)), file: file, line: line)
    }

    func testAcceptsOrdinaryExtensionLayout() throws {
        let entries = try ZipArchiveScanner.scan(ZipBuilder.build([
            .init(name: "manifest.json", data: Data("{}".utf8)),
            .init(name: "icons/"),
            .init(name: "icons/icon-48.png", data: Data([1, 2, 3])),
            .init(name: "_locales/en/messages.json", data: Data("{}".utf8)),
            .init(name: "a..b/file..js"),      // ".." inside a name is not a component
        ]))
        XCTAssertEqual(entries.map(\.name), ["manifest.json", "icons/", "icons/icon-48.png", "_locales/en/messages.json", "a..b/file..js"])
        XCTAssertEqual(entries.map(\.isDirectory), [false, true, false, false, false])
    }

    func testAcceptsArchiveComment() throws {
        let zip = ZipBuilder.build([.init(name: "manifest.json")], comment: Data("hello".utf8))
        XCTAssertEqual(try ZipArchiveScanner.scan(zip).count, 1)
    }

    func testRefusesAbsolutePaths() {
        assertRefused([.init(name: "/etc/passwd")])
        assertRefused([.init(name: "\\Windows\\x")])
        assertRefused([.init(name: "C:/x")])
    }

    func testRefusesParentComponents() {
        assertRefused([.init(name: "../evil.js")])
        assertRefused([.init(name: "a/../../evil.js")])
        assertRefused([.init(name: "a/b/../../../evil.js")])
        assertRefused([.init(name: "..\\evil.js")])
        assertRefused([.init(name: "a\\..\\..\\evil.js")])
        assertRefused([.init(name: "dir/..")])
    }

    func testRefusesNulAndEmptyNames() {
        assertRefused([.init(name: "")])
        assertRefused([.init(name: "a\0b")])
    }

    func testRefusesSymlinksAndSpecialFiles() {
        assertRefused([.init(name: "link", data: Data("/etc".utf8), unixMode: 0o120777)])
        assertRefused([.init(name: "fifo", unixMode: 0o010644)])
    }

    func testAcceptsUnixRegularFilesAndFolders() throws {
        _ = try ZipArchiveScanner.scan(ZipBuilder.build([
            .init(name: "manifest.json", unixMode: 0o100644),
            .init(name: "sub/", unixMode: 0o040755),
        ]))
    }

    func testRefusesEncryptedEntries() {
        assertRefused([.init(name: "manifest.json", flags: 0x1)])
    }

    func testRefusesLocalHeaderNameMismatch() {
        // Central directory looks harmless; the local header an extractor may use does not.
        assertRefused([.init(name: "manifest.json", localName: "../evil.js")])
    }

    func testRefusesBadStructure() {
        XCTAssertThrowsError(try ZipArchiveScanner.scan(Data()))
        XCTAssertThrowsError(try ZipArchiveScanner.scan(Data(repeating: 0, count: 64)))
        let good = ZipBuilder.build([.init(name: "manifest.json")])
        XCTAssertThrowsError(try ZipArchiveScanner.scan(good.dropLast(5)))
    }

    func testPathReasonHelper() {
        XCTAssertNil(ZipArchiveScanner.unsafeReason(for: "js/background.js"))
        XCTAssertNotNil(ZipArchiveScanner.unsafeReason(for: "x/../../y"))
    }

    func testVerifyExtractedTreeRejectsSymlink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("alp-zip-test-\(UUID().uuidString)", isDirectory: true)
        let tree = root.appendingPathComponent("tree", isDirectory: true)
        try fm.createDirectory(at: tree, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try Data("{}".utf8).write(to: tree.appendingPathComponent("manifest.json"))
        XCTAssertNoThrow(try ZipArchiveScanner.verifyExtractedTree(at: tree))

        try fm.createSymbolicLink(at: tree.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        XCTAssertThrowsError(try ZipArchiveScanner.verifyExtractedTree(at: tree))
    }
}
