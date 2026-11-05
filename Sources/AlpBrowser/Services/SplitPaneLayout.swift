//
//  SplitPaneLayout.swift
//  Alp Browser
//
//  Pure sizing maths for 3- and 4-pane Split View (the 2-pane case keeps its single ratio).
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation

/// Pane sizes for a split with three or more panes, as fractions of the shared extent that sum to 1.
/// Dragging the divider between pane `i` and pane `i + 1` only moves space between those two panes.
public enum SplitPaneLayout {
    /// Smallest share any pane may be dragged to.
    public static let minFraction: Double = 0.12

    /// Fractions for `count` panes: `raw` when it fits (right length, finite, positive), scaled to sum 1 and
    /// with every pane raised to `minFraction`; an even split otherwise.
    public static func normalized(_ raw: [Double]?, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let even = [Double](repeating: 1.0 / Double(count), count: count)
        guard count > 1,
              let raw, raw.count == count,
              raw.allSatisfy({ $0.isFinite && $0 > 0 }),
              minFraction * Double(count) < 1 else { return even }

        let total = raw.reduce(0, +)
        var result = raw.map { $0 / total }

        // Pin panes that fall under the minimum and shrink the rest to make room; repeat because
        // shrinking can push another pane under.
        var pinned = Set<Int>()
        for _ in 0..<count {
            let newlyLow = result.indices.filter { !pinned.contains($0) && result[$0] < minFraction - 1e-9 }
            if newlyLow.isEmpty { break }
            pinned.formUnion(newlyLow)
            let freeIndices = result.indices.filter { !pinned.contains($0) }
            let freeTotal = freeIndices.reduce(0.0) { $0 + result[$1] }
            guard freeTotal > 0 else { return even }
            let scale = (1 - minFraction * Double(pinned.count)) / freeTotal
            for i in result.indices {
                result[i] = pinned.contains(i) ? minFraction : result[i] * scale
            }
        }
        return result
    }

    /// Share of the two panes around `boundary` that the first one holds (0...1).
    public static func pairShare(_ fractions: [Double], boundary: Int) -> Double {
        guard fractions.indices.contains(boundary), fractions.indices.contains(boundary + 1) else { return 0.5 }
        let pair = fractions[boundary] + fractions[boundary + 1]
        return pair > 0 ? fractions[boundary] / pair : 0.5
    }

    /// Lowest and highest `pairShare` the boundary may take so neither neighbour drops under `minFraction`.
    public static func pairShareRange(_ fractions: [Double], boundary: Int) -> ClosedRange<Double> {
        guard fractions.indices.contains(boundary), fractions.indices.contains(boundary + 1) else { return 0.2...0.8 }
        let pair = fractions[boundary] + fractions[boundary + 1]
        guard pair > 2 * minFraction else { return 0.5...0.5 }
        return (minFraction / pair)...(1 - minFraction / pair)
    }

    /// Moves the boundary so the first pane of the pair holds `share` of the pair's combined size.
    /// Other panes are untouched and the total stays 1.
    public static func settingPairShare(_ fractions: [Double], boundary: Int, share: Double) -> [Double] {
        guard fractions.indices.contains(boundary), fractions.indices.contains(boundary + 1), share.isFinite else {
            return fractions
        }
        let pair = fractions[boundary] + fractions[boundary + 1]
        let range = pairShareRange(fractions, boundary: boundary)
        let clamped = min(range.upperBound, max(range.lowerBound, share))
        var result = fractions
        result[boundary] = pair * clamped
        result[boundary + 1] = pair - result[boundary]
        return result
    }

    /// Size of one keyboard nudge, as a fraction of the whole split.
    public static let keyboardStep: Double = 0.03

    /// Bounds of the single ratio used by a 2-pane split.
    public static let twoPaneRange: ClosedRange<Double> = 0.2...0.8

    /// 2-pane ratio (share of the first pane) after pane `pane` (0 or 1) changes size by `delta` of the whole.
    public static func nudgedTwoPaneRatio(_ ratio: Double, pane: Int, delta: Double) -> Double {
        let base = ratio.isFinite ? ratio : 0.5
        let moved = pane == 0 ? base + delta : base - delta
        return min(twoPaneRange.upperBound, max(twoPaneRange.lowerBound, moved))
    }

    /// Fractions after pane `pane` changes size by `delta` of the whole (negative shrinks). The space comes from / goes to
    /// the neighbour after it (before it for the last pane); the pair is clamped so neither drops under `minFraction`.
    public static func resizingPane(_ fractions: [Double], pane: Int, delta: Double) -> [Double] {
        guard fractions.count > 1, fractions.indices.contains(pane), delta.isFinite else { return fractions }
        let boundary = pane < fractions.count - 1 ? pane : pane - 1
        let pair = fractions[boundary] + fractions[boundary + 1]
        guard pair > 0 else { return fractions }
        let share = pairShare(fractions, boundary: boundary)
        let moved = pane == boundary ? share + delta / pair : share - delta / pair
        return settingPairShare(fractions, boundary: boundary, share: moved)
    }

    /// `items` with the element at `index` swapped with its neighbour one position forward (or backward).
    /// Nil at either end (no wrapping) or for a bad index. Used for pane ids and pane sizes alike, so a pane keeps its size.
    public static func swappingNeighbour<T>(_ items: [T], index: Int, forward: Bool) -> [T]? {
        let other = forward ? index + 1 : index - 1
        guard items.indices.contains(index), items.indices.contains(other) else { return nil }
        var result = items
        result.swapAt(index, other)
        return result
    }
}
