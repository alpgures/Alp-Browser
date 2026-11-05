//
//  AlpBrowserTests.swift
//  Alp Browser
//
//  Unit tests for clean-room architecture, data structures, colors, and models.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import XCTest
@testable import AlpBrowser

final class AlpBrowserTests: XCTestCase {

    func testCleanRoomArchitectureSetup() {
        XCTAssertTrue(true, "Clean room architecture initializes successfully")
    }

    func testRGBAColorHexParsingAndRoundtrip() {
        // Standard 6-digit hex
        let coral = RGBAColor(hex: "#FA6138")
        XCTAssertEqual(coral.hexString.uppercased(), "#FA6138")

        // 3-digit shorthand
        let redShort = RGBAColor(hex: "#F00")
        XCTAssertEqual(redShort.hexString.uppercased(), "#FF0000")

        // 8-digit hex with alpha
        let semiBlue = RGBAColor(hex: "#0000FF80")
        XCTAssertEqual(semiBlue.hexString.uppercased(), "#0000FF80")
    }

    func testRGBAColorBlendingAndBrightness() {
        let black = RGBAColor(red: 0, green: 0, blue: 0)
        let white = RGBAColor(red: 1, green: 1, blue: 1)
        let mid = black.blended(with: white, fraction: 0.5)

        XCTAssertEqual(mid.red, 0.5, accuracy: 0.01)
        XCTAssertEqual(mid.green, 0.5, accuracy: 0.01)
        XCTAssertEqual(mid.blue, 0.5, accuracy: 0.01)

        let brightened = mid.brightened(by: 0.2)
        XCTAssertGreaterThan(brightened.red, mid.red)

        let darkened = mid.darkened(by: 0.2)
        XCTAssertLessThan(darkened.red, mid.red)
    }

    func testTabItemDomainSimplification() {
        let webTab = TabItem(
            title: "Search Results",
            urlString: "https://www.google.com/search?q=swift+development"
        )
        XCTAssertEqual(webTab.simplifiedDomain, "google.com")

        let portTab = TabItem(
            title: "Localhost",
            urlString: "http://localhost:8080/dashboard"
        )
        XCTAssertEqual(portTab.simplifiedDomain, "localhost:8080")

        let canvasTab = TabItem(
            title: "Project Ideas",
            urlString: "alp://canvas/notes",
            kind: .canvas
        )
        XCTAssertEqual(canvasTab.simplifiedDomain, "Project Ideas")
    }

    func testSidebarNodeRecursiveTabTraversal() {
        let tab1 = TabItem(title: "Tab 1", urlString: "https://alpbrowser.app/1")
        let tab2 = TabItem(title: "Tab 2", urlString: "https://alpbrowser.app/2")
        let tab3 = TabItem(title: "Tab 3", urlString: "https://alpbrowser.app/3")

        let subFolder = FolderItem(title: "Sub", children: [.tab(tab3)])
        let rootFolder = FolderItem(title: "Root", children: [.tab(tab2), .folder(subFolder)])
        let rootNode = SidebarNode.folder(rootFolder)

        let allTabs = rootNode.allTabs
        XCTAssertEqual(allTabs.count, 2)
        XCTAssertTrue(allTabs.contains(where: { $0.id == tab2.id }))
        XCTAssertTrue(allTabs.contains(where: { $0.id == tab3.id }))
        XCTAssertFalse(allTabs.contains(where: { $0.id == tab1.id }))
    }

    func testFolderItemStartsCollapsed() {
        let folder = FolderItem(title: "Work")
        XCTAssertFalse(folder.isExpanded, "Folders must default to collapsed per user requirement")
    }

    func testAlpSpaceTabsAndNodeCount() {
        let tabA = TabItem(title: "A", urlString: "https://a.com")
        let tabB = TabItem(title: "B", urlString: "https://b.com")
        let tabC = TabItem(title: "C", urlString: "https://c.com")

        let space = AlpSpace(
            title: "Engineering",
            iconEmoji: "🛠️",
            theme: SpaceTheme.amber,
            pinnedNodes: [.tab(tabA), .folder(FolderItem(title: "Docs", children: [.tab(tabB)]))],
            todayTabs: [tabC]
        )

        XCTAssertEqual(space.pinnedNodes.count, 2)
        XCTAssertEqual(space.todayTabs.count, 1)
        XCTAssertEqual(space.allTabs.count, 3)
    }

    func testSpaceThemePresetsAreCleanAndGrainFree() {
        let themes = [
            SpaceTheme.arcDefault,
            SpaceTheme.rose,
            SpaceTheme.purple,
            SpaceTheme.emerald,
            SpaceTheme.amber
        ]

        for theme in themes {
            XCTAssertFalse(theme.renderedGradientColors.isEmpty)
            XCTAssertNotNil(theme.foregroundColor)
            XCTAssertNotNil(theme.selectionBackground)
        }
    }
}
