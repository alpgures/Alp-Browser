import XCTest
import AppKit
@testable import AlpBrowser

@MainActor
final class NoteMarkdownStylerTests: XCTestCase {
    private func styled(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        NoteMarkdownStyler.restyle(storage)
        return storage
    }

    private func font(_ storage: NSTextStorage, at index: Int) -> NSFont? {
        storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func isBold(_ font: NSFont?) -> Bool {
        font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
    }

    private func isItalic(_ font: NSFont?) -> Bool {
        font.map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) } ?? false
    }

    func testStylingNeverChangesTheMarkdownSource() {
        let source = "# Title\n**bold** and *it* and `code`\n- item\n> quote\n"
        XCTAssertEqual(styled(source).string, source)
    }

    func testBoldItalicCode() {
        let storage = styled("a **bold** b *it* c `code`")
        XCTAssertFalse(isBold(font(storage, at: 0)))
        XCTAssertTrue(isBold(font(storage, at: 5)))
        XCTAssertTrue(isItalic(font(storage, at: 15)))
        XCTAssertFalse(isItalic(font(storage, at: 0)))
        XCTAssertTrue(font(storage, at: 22)?.isFixedPitch ?? false)
    }

    func testMarkersAreDimmed() {
        let storage = styled("**bold**")
        let marker = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(marker, NSColor.tertiaryLabelColor)
        let inner = storage.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor
        XCTAssertEqual(inner, NSColor.labelColor)
    }

    func testHeadingIsLargerAndBold() {
        let storage = styled("# Title\nplain")
        XCTAssertGreaterThan(font(storage, at: 3)?.pointSize ?? 0, NoteMarkdownStyler.baseSize)
        XCTAssertTrue(isBold(font(storage, at: 3)))
        XCTAssertEqual(font(storage, at: 10)?.pointSize ?? 0, NoteMarkdownStyler.baseSize, accuracy: 0.01)
    }

    func testListAndQuote() {
        let storage = styled("- item\n> quote")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.controlAccentColor)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor, NSColor.secondaryLabelColor)
    }

    func testMarkersInsideCodeAreNotEmphasis() {
        let storage = styled("`a *b* c`")
        XCTAssertFalse(isItalic(font(storage, at: 4)))
    }

    func testUnbalancedMarkersStayPlain() {
        let storage = styled("2 * 3 and **open")
        XCTAssertFalse(isBold(font(storage, at: 12)))
        XCTAssertFalse(isItalic(font(storage, at: 0)))
    }

    func testPartialRestyleClearsOldStyling() {
        let storage = styled("**bold**\nplain")
        storage.replaceCharacters(in: NSRange(location: 0, length: 8), with: "bold")
        NoteMarkdownStyler.restyle(storage, in: NSRange(location: 0, length: 5))
        XCTAssertFalse(isBold(font(storage, at: 0)))
    }

    // MARK: Gaps closed in run 8

    func testTripleStarIsBoldAndItalic() {
        let storage = styled("a ***both*** b")
        XCTAssertTrue(isBold(font(storage, at: 7)))
        XCTAssertTrue(isItalic(font(storage, at: 7)))
        XCTAssertFalse(isBold(font(storage, at: 0)))
        XCTAssertFalse(isItalic(font(storage, at: 13)))
        // All three stars on each side are dimmed markers.
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, NSColor.tertiaryLabelColor)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor, NSColor.tertiaryLabelColor)
    }

    func testOrderedListNumberIsAccentColoured() {
        let storage = styled("1. first\n12) second\n3.nospace")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.controlAccentColor)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, NSColor.controlAccentColor)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, NSColor.labelColor)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor, NSColor.controlAccentColor)
        // No space after the dot: not a list item.
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 20, effectiveRange: nil) as? NSColor, NSColor.labelColor)
    }

    func testFencedCodeBlockIsMonospacedAndOpaque() {
        let source = "before\n```swift\nlet a = *x* + **y**\n# not a heading\n```\nafter *it*"
        let storage = styled(source)
        XCTAssertEqual(storage.string, source)
        let body = (source as NSString).range(of: "let a")
        XCTAssertTrue(font(storage, at: body.location)?.isFixedPitch ?? false)
        let star = (source as NSString).range(of: "*x*")
        XCTAssertFalse(isItalic(font(storage, at: star.location + 1)))
        let hash = (source as NSString).range(of: "# not")
        XCTAssertEqual(font(storage, at: hash.location + 3)?.pointSize ?? 0, NoteMarkdownStyler.baseSize * 0.92, accuracy: 0.01)
        // Fence lines are dimmed; text outside the block is untouched.
        let fence = (source as NSString).range(of: "```swift")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: fence.location, effectiveRange: nil) as? NSColor, NSColor.tertiaryLabelColor)
        XCTAssertFalse(font(storage, at: 0)?.isFixedPitch ?? true)
        let after = (source as NSString).range(of: "it")
        XCTAssertTrue(isItalic(font(storage, at: after.location)))
    }

    func testUnclosedFenceAndInlineTripleBackticksStayPlain() {
        let open = styled("```\nstill *plain* text")
        XCTAssertFalse(font(open, at: 0)?.isFixedPitch ?? false)
        XCTAssertTrue(isItalic(font(open, at: 12)))
        let inline = styled("```code``` here")
        // Inline code on one line, not a fence: no fence marker attribute on the line.
        XCTAssertNil(inline.attribute(NSAttributedString.Key("alpNoteFence"), at: 8, effectiveRange: nil))
    }

    func testClosingAFenceRestylesTheLinesBetween() {
        let storage = styled("```\n*x*\n")
        XCTAssertTrue(isItalic(font(storage, at: 5)))
        // Type the closing fence at the end, restyling only the edited line.
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "```")
        NoteMarkdownStyler.restyle(storage, in: NSRange(location: storage.length - 3, length: 3))
        XCTAssertFalse(isItalic(font(storage, at: 5)))
        XCTAssertTrue(font(storage, at: 5)?.isFixedPitch ?? false)
        // Remove it again: the body goes back to normal styling.
        storage.replaceCharacters(in: NSRange(location: storage.length - 3, length: 3), with: "")
        // An empty range at the end touches no line: the fence status scan alone must catch the change.
        NoteMarkdownStyler.restyle(storage, in: NSRange(location: storage.length, length: 0))
        XCTAssertTrue(isItalic(font(storage, at: 5)))
    }

    func testBackslashEscapesDisableMarkers() {
        let storage = styled("\\*not italic\\* and \\**x\\**")
        XCTAssertFalse(isItalic(font(storage, at: 3)))
        XCTAssertFalse(isBold(font(storage, at: 3)))
        // The backslash is dimmed, the escaped star is not.
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.tertiaryLabelColor)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, NSColor.labelColor)
        // An escaped star inside real emphasis does not close it.
        let inner = styled("*a \\* b*")
        XCTAssertTrue(isItalic(font(inner, at: 1)))
        XCTAssertTrue(isItalic(font(inner, at: 6)))
    }

    func testEscapedLineStartIsNotAHeadingOrList() {
        let heading = styled("\\# not a heading")
        XCTAssertEqual(font(heading, at: 5)?.pointSize ?? 0, NoteMarkdownStyler.baseSize, accuracy: 0.01)
        let list = styled("\\- not a list")
        XCTAssertEqual(list.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, NSColor.labelColor)
        // A doubled backslash is a literal backslash, so the star after it still starts emphasis.
        let literal = styled("\\\\*it*")
        XCTAssertTrue(isItalic(font(literal, at: 3)))
    }
}
