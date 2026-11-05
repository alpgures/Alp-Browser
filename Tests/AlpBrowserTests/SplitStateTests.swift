import XCTest
@testable import AlpBrowser

final class SplitStatePersistenceTests: XCTestCase {
    private func decode(_ json: String) throws -> PersistedBrowserStore {
        try JSONDecoder().decode(PersistedBrowserStore.self, from: Data(json.utf8))
    }

    func testStoreWithoutSplitRatioDefaultsToEven() throws {
        XCTAssertEqual(try decode("{}").splitRatio, 0.5, accuracy: 0.0001)
    }

    func testSplitRatioRoundTrips() throws {
        var store = PersistedBrowserStore()
        store.splitRatio = 0.35
        let data = try JSONEncoder().encode(store)
        let back = try JSONDecoder().decode(PersistedBrowserStore.self, from: data)
        XCTAssertEqual(back.splitRatio, 0.35, accuracy: 0.0001)
    }

    func testOutOfRangeRatioIsClamped() throws {
        XCTAssertEqual(try decode("{\"splitRatio\": 0.01}").splitRatio, 0.2, accuracy: 0.0001)
        XCTAssertEqual(try decode("{\"splitRatio\": 7}").splitRatio, 0.8, accuracy: 0.0001)
    }

    func testSpaceSplitStateRoundTrips() throws {
        let ids = [UUID(), UUID()]
        let space = AlpSpace(title: "S", splitPaneTabIDs: ids, splitOrientation: .vertical)
        let back = try JSONDecoder().decode(AlpSpace.self, from: JSONEncoder().encode(space))
        XCTAssertEqual(back.splitPaneTabIDs, ids)
        XCTAssertEqual(back.splitOrientation, .vertical)
    }

    func testOldSpaceWithoutFractionsStillDecodes() throws {
        let space = AlpSpace(title: "S", splitFractions: [0.5, 0.25, 0.25])
        let data = try JSONEncoder().encode(space)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["splitFractions"])
        object.removeValue(forKey: "splitFractions")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(AlpSpace.self, from: old).splitFractions)
    }

    func testSpaceFractionsRoundTrip() throws {
        let space = AlpSpace(title: "S", splitFractions: [0.5, 0.3, 0.2])
        let back = try JSONDecoder().decode(AlpSpace.self, from: JSONEncoder().encode(space))
        XCTAssertEqual(back.splitFractions, [0.5, 0.3, 0.2])
    }
}

final class SplitPaneLayoutTests: XCTestCase {
    func testMissingOrMismatchedFractionsBecomeEven() {
        XCTAssertEqual(SplitPaneLayout.normalized(nil, count: 4), [0.25, 0.25, 0.25, 0.25])
        XCTAssertEqual(SplitPaneLayout.normalized([0.5, 0.5], count: 3).count, 3)
        XCTAssertEqual(SplitPaneLayout.normalized([0.5, 0.5], count: 3)[0], 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(SplitPaneLayout.normalized([0.5, .nan, 0.5], count: 3)[0], 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(SplitPaneLayout.normalized([0.5, -1, 0.5], count: 3)[1], 1.0 / 3, accuracy: 0.0001)
    }

    func testNormalizedSumsToOneAndHonoursMinimum() {
        let result = SplitPaneLayout.normalized([0.01, 0.5, 0.3, 0.19], count: 4)
        XCTAssertEqual(result.reduce(0, +), 1, accuracy: 0.0001)
        for value in result { XCTAssertGreaterThanOrEqual(value, SplitPaneLayout.minFraction - 0.0001) }
        let scaled = SplitPaneLayout.normalized([2, 1, 1], count: 3)
        XCTAssertEqual(scaled[0], 0.5, accuracy: 0.0001)
    }

    func testDraggingABoundaryOnlyMovesItsTwoNeighbours() {
        let start = [0.25, 0.25, 0.25, 0.25]
        let share = SplitPaneLayout.pairShare(start, boundary: 1)
        XCTAssertEqual(share, 0.5, accuracy: 0.0001)
        let moved = SplitPaneLayout.settingPairShare(start, boundary: 1, share: 0.7)
        XCTAssertEqual(moved[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(moved[3], 0.25, accuracy: 0.0001)
        XCTAssertEqual(moved[1], 0.35, accuracy: 0.0001)
        XCTAssertEqual(moved[2], 0.15, accuracy: 0.0001)
        XCTAssertEqual(moved.reduce(0, +), 1, accuracy: 0.0001)
    }

    func testDraggingPastTheLimitStopsAtTheMinimum() {
        let start = [1.0 / 3, 1.0 / 3, 1.0 / 3]
        let pushed = SplitPaneLayout.settingPairShare(start, boundary: 0, share: 5)
        XCTAssertEqual(pushed[1], SplitPaneLayout.minFraction, accuracy: 0.0001)
        XCTAssertEqual(pushed.reduce(0, +), 1, accuracy: 0.0001)
        let pulled = SplitPaneLayout.settingPairShare(start, boundary: 0, share: -3)
        XCTAssertEqual(pulled[0], SplitPaneLayout.minFraction, accuracy: 0.0001)
    }

    func testKeyboardNudgeTwoPaneRespectsBoundsAndPaneSide() {
        let step = SplitPaneLayout.keyboardStep
        XCTAssertEqual(SplitPaneLayout.nudgedTwoPaneRatio(0.5, pane: 0, delta: step), 0.5 + step, accuracy: 0.0001)
        XCTAssertEqual(SplitPaneLayout.nudgedTwoPaneRatio(0.5, pane: 1, delta: step), 0.5 - step, accuracy: 0.0001)
        XCTAssertEqual(SplitPaneLayout.nudgedTwoPaneRatio(0.79, pane: 0, delta: step), 0.8, accuracy: 0.0001)
        XCTAssertEqual(SplitPaneLayout.nudgedTwoPaneRatio(0.21, pane: 0, delta: -step), 0.2, accuracy: 0.0001)
        XCTAssertEqual(SplitPaneLayout.nudgedTwoPaneRatio(.nan, pane: 0, delta: step), 0.5 + step, accuracy: 0.0001)
    }

    func testSwappingNeighbourMovesOneStepAndStopsAtTheEnds() {
        XCTAssertEqual(SplitPaneLayout.swappingNeighbour(["a", "b", "c"], index: 1, forward: true) ?? [], ["a", "c", "b"])
        XCTAssertEqual(SplitPaneLayout.swappingNeighbour(["a", "b", "c"], index: 1, forward: false) ?? [], ["b", "a", "c"])
        XCTAssertNil(SplitPaneLayout.swappingNeighbour(["a", "b", "c"], index: 2, forward: true))
        XCTAssertNil(SplitPaneLayout.swappingNeighbour(["a", "b", "c"], index: 0, forward: false))
        XCTAssertNil(SplitPaneLayout.swappingNeighbour(["a"], index: 5, forward: true))
        let sizes = SplitPaneLayout.swappingNeighbour([0.5, 0.3, 0.2], index: 0, forward: true) ?? []
        XCTAssertEqual(sizes, [0.3, 0.5, 0.2])
    }

    func testKeyboardNudgeMultiPaneTradesWithNeighbourAndKeepsMinimum() {
        let even3 = [1.0 / 3, 1.0 / 3, 1.0 / 3]
        let grown = SplitPaneLayout.resizingPane(even3, pane: 0, delta: 0.03)
        XCTAssertEqual(grown[0], 1.0 / 3 + 0.03, accuracy: 0.0001)
        XCTAssertEqual(grown[1], 1.0 / 3 - 0.03, accuracy: 0.0001)
        XCTAssertEqual(grown[2], 1.0 / 3, accuracy: 0.0001)
        // The last pane trades with the one before it.
        let last = SplitPaneLayout.resizingPane(even3, pane: 2, delta: 0.03)
        XCTAssertEqual(last[2], 1.0 / 3 + 0.03, accuracy: 0.0001)
        XCTAssertEqual(last[1], 1.0 / 3 - 0.03, accuracy: 0.0001)
        // Repeated shrinking stops at the minimum, in a 4-pane split too.
        var fractions = [0.25, 0.25, 0.25, 0.25]
        for _ in 0..<50 { fractions = SplitPaneLayout.resizingPane(fractions, pane: 1, delta: -0.03) }
        XCTAssertEqual(fractions[1], SplitPaneLayout.minFraction, accuracy: 0.0001)
        XCTAssertEqual(fractions.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(fractions[0], 0.25, accuracy: 0.0001)
        // Bad input is returned unchanged.
        XCTAssertEqual(SplitPaneLayout.resizingPane(even3, pane: 7, delta: 0.03), even3)
    }
}
