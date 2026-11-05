import XCTest
@testable import AlpBrowser

final class AlpSidebarImporterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("alp-importer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ text: String) throws -> URL {
        let url = directory.appendingPathComponent("StorableSidebar.json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func tab(_ id: String, parent: String, url: String, title: String = "T") -> String {
        """
        {"id":"\(id)","title":"\(title)","parentID":"\(parent)","data":{"tab":{"savedURL":"\(url)","savedTitle":"\(title)"}}}
        """
    }

    /// One space "S1" whose Today list is `unpinned` (tab items) with no explicit child lists (parent index is used).
    private func sidebar(items: [String], spaces: String = #"[{"id":"S1","title":"Work","containerIDs":["pinned","P","unpinned","U"]}]"#) -> String {
        let containers = [#"{"id":"P","parentID":"S1"}"#, #"{"id":"U","parentID":"S1"}"#] + items
        return #"{"sidebar":{"containers":[{"global":{}},{"spaces":\#(spaces),"items":[\#(containers.joined(separator: ","))]}]}}"#
    }

    private func assertFails(_ text: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try write(text)
        XCTAssertThrowsError(try AlpSidebarImporter.importFromArc(at: url), file: file, line: line) { error in
            XCTAssertTrue(error.localizedDescription.contains(expected), "\(error.localizedDescription)", file: file, line: line)
        }
    }

    func testMissingFileSaysNotFound() {
        let url = directory.appendingPathComponent("nope.json")
        XCTAssertThrowsError(try AlpSidebarImporter.importFromArc(at: url)) { error in
            XCTAssertTrue(error is ArcImportError)
            XCTAssertTrue(error.localizedDescription.contains("not found"))
        }
    }

    func testMalformedAndTruncatedFilesFailWithAClearMessage() throws {
        try assertFails("this is not json", "not in a format")
        try assertFails(#"{"sidebar":{"containers":[{"spaces":[{"id":"S1""#, "not in a format")
        try assertFails(#"{"sidebar":{}}"#, "not in a format")
        try assertFails(#"{"sidebar":{"containers":[{"global":{}}]}}"#, "not in a format")
    }

    func testNoSpacesIsAnErrorNotAnEmptyImport() throws {
        try assertFails(sidebar(items: [], spaces: "[]"), "No spaces")
        try assertFails(sidebar(items: [], spaces: #"[{"title":"no id"}, 7, null]"#), "No spaces")
    }

    func testImportsTabsInFileOrderAndDropsDuplicatesAndUnsafeURLs() throws {
        let items = [
            tab("a", parent: "U", url: "https://one.example"),
            tab("b", parent: "U", url: "https://two.example"),
            tab("c", parent: "U", url: "https://one.example"),
            tab("d", parent: "U", url: "arc://settings"),
            tab("e", parent: "U", url: "javascript:alert(1)"),
            tab("f", parent: "U", url: "")
        ]
        let data = try AlpSidebarImporter.importFromArc(at: try write(sidebar(items: items)))
        XCTAssertEqual(data.spaces.count, 1)
        XCTAssertEqual(data.spaces[0].title, "Work")
        XCTAssertEqual(data.spaces[0].todayTabs.map { $0.urlString }, ["https://one.example", "https://two.example"])
        XCTAssertEqual(data.totalImportedTabs, 2)
        XCTAssertEqual(data.skippedItems, 3)   // duplicate, arc://, javascript:
    }

    func testDuplicateSpaceIDsAndMissingTitlesAreHandled() throws {
        let spaces = #"[{"id":"S1","title":"  ","containerIDs":["pinned","P","unpinned","U"]},{"id":"S1","title":"Again"}]"#
        let data = try AlpSidebarImporter.importFromArc(at: try write(sidebar(items: [], spaces: spaces)))
        XCTAssertEqual(data.spaces.count, 1)
        XCTAssertEqual(data.spaces[0].title, "Space 1")
        XCTAssertNil(data.spaces[0].activeTabID)
    }

    func testFolderCycleAndDeepNestingTerminate() throws {
        var items = [
            #"{"id":"F1","title":"loop","parentID":"P","data":{"list":{}},"childrenIds":["F2"]}"#,
            #"{"id":"F2","title":"loop2","parentID":"F1","data":{"list":{}},"childrenIds":["F1"]}"#
        ]
        // A chain far deeper than any real sidebar.
        for i in 0..<200 {
            let parent = i == 0 ? "P" : "D\(i - 1)"
            items.append(#"{"id":"D\#(i)","title":"d","parentID":"\#(parent)","data":{"list":{}},"childrenIds":["D\#(i + 1)"]}"#)
        }
        let spaces = #"[{"id":"S1","title":"Work","containerIDs":["pinned","P","unpinned","U"]}]"#
        let data = try AlpSidebarImporter.importFromArc(at: try write(sidebar(items: items, spaces: spaces)))
        XCTAssertEqual(data.spaces.count, 1)
        XCTAssertGreaterThan(data.skippedItems, 0)
    }

    func testVeryLargeTabCountIsCappedAndReported() throws {
        let count = AlpSidebarImporter.maxImportedItems + 50
        let items = (0..<count).map { tab("t\($0)", parent: "U", url: "https://example.com/\($0)") }
        let data = try AlpSidebarImporter.importFromArc(at: try write(sidebar(items: items)))
        XCTAssertEqual(data.totalImportedTabs, AlpSidebarImporter.maxImportedItems)
        XCTAssertEqual(data.skippedItems, 50)
    }

    func testURLFilter() {
        XCTAssertEqual(AlpSidebarImporter.cleanedURL("  https://a.example/x  "), "https://a.example/x")
        XCTAssertNotNil(AlpSidebarImporter.cleanedURL("HTTP://A.EXAMPLE"))
        XCTAssertNil(AlpSidebarImporter.cleanedURL("arc://settings"))
        XCTAssertNil(AlpSidebarImporter.cleanedURL("data:text/html,hi"))
        XCTAssertNil(AlpSidebarImporter.cleanedURL(String(repeating: "a", count: 9000)))
    }
}
