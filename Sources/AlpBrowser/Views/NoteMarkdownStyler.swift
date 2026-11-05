//
//  NoteMarkdownStyler.swift
//  Alp Browser
//
//  Live markdown styling for the note editor. Only changes attributes: the characters (the markdown
//  source that is saved) are never touched.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import AppKit

/// Styles the formats the note toolbar writes: bold `**x**`, italic `*x*`, code `` `x` ``, heading `# x`, list `- x`
/// and quote `> x`; plus bold+italic `***x***`, ordered lists `1. x`, fenced code blocks and backslash escapes.
/// Markers stay visible but are dimmed. Everything is line based, so an edit only needs its own lines restyled
/// (plus any line whose fenced-code status the edit flipped, found with a cheap whole-text line scan).
@MainActor
enum NoteMarkdownStyler {
    static let baseSize: CGFloat = 15
    static let lineSpacing: CGFloat = 6

    static var baseFont: NSFont { NSFont.systemFont(ofSize: baseSize) }

    static func baseParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    /// Attributes for unstyled text; also used as the editor's typing attributes.
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    // MARK: Patterns (compiled once)

    private static let headingPattern = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+")
    private static let listPattern = try! NSRegularExpression(pattern: "^[ \\t]*([-*+])[ \\t]+")
    private static let orderedListPattern = try! NSRegularExpression(pattern: "^[ \\t]*(\\d{1,9}[.)])[ \\t]+")
    private static let quotePattern = try! NSRegularExpression(pattern: "^>[ \\t]?")
    private static let codePattern = try! NSRegularExpression(pattern: "`[^`\\n]+`")
    private static let boldItalicPattern = try! NSRegularExpression(pattern: "(?<!\\*)\\*\\*\\*(?![*\\s])[^*\\n]+?(?<![\\s*])\\*\\*\\*(?!\\*)")
    private static let boldPattern = try! NSRegularExpression(pattern: "\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*")
    private static let italicPattern = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?![*\\s])[^*\\n]+?(?<![\\s*])\\*(?!\\*)")

    /// Marks lines that belong to a fenced code block, so a later edit can tell which lines changed status.
    private static let fenceKey = NSAttributedString.Key("alpNoteFence")

    private enum LineKind { case normal, fenceDelimiter, fenceBody }

    private struct LineInfo {
        let line: NSRange      // including the line break
        let content: NSRange   // without the line break
        var kind: LineKind
    }

    // MARK: Entry point

    /// Restyles the lines touched by `range` (the whole text when nil), and any line whose fenced-code status
    /// the edit changed. Text is not modified, so this registers no undo step and does not trigger a text-change callback.
    static func restyle(_ storage: NSTextStorage, in range: NSRange? = nil) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        guard full.length > 0 else { return }

        var target = full
        if let range {
            let location = min(range.location, full.length)
            target = NSRange(location: location, length: min(range.length, full.length - location))
        }
        target = text.lineRange(for: target)

        let lines = scanLines(text)
        storage.beginEditing()
        for info in lines {
            let touched = NSIntersectionRange(info.line, target).length > 0
            let wasFenced = storage.attribute(fenceKey, at: info.line.location, effectiveRange: nil) != nil
            guard touched || wasFenced != (info.kind != .normal) else { continue }
            storage.setAttributes(baseAttributes, range: info.line)
            switch info.kind {
            case .normal:
                style(line: info.content, in: storage, text: text)
            case .fenceDelimiter, .fenceBody:
                styleFence(info, in: storage)
            }
        }
        storage.endEditing()
    }

    // MARK: Fenced code blocks

    /// Splits the text into lines and marks which belong to a closed fenced code block. An opening fence with no
    /// closing fence is left plain, like other unbalanced markers.
    private static func scanLines(_ text: NSString) -> [LineInfo] {
        var lines: [LineInfo] = []
        var location = 0
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            guard line.length > 0 else { break }
            lines.append(LineInfo(line: line, content: contentRange(of: line, in: text), kind: .normal))
            location = NSMaxRange(line)
        }

        var open: (index: Int, marker: unichar, count: Int)?
        for index in lines.indices {
            guard let fence = fenceMarker(in: text, content: lines[index].content) else { continue }
            if let pending = open {
                if fence.marker == pending.marker, fence.count >= pending.count, !fence.hasInfo {
                    for inner in pending.index...index {
                        lines[inner].kind = (inner == pending.index || inner == index) ? .fenceDelimiter : .fenceBody
                    }
                    open = nil
                }
            } else {
                open = (index, fence.marker, fence.count)
            }
        }
        return lines
    }

    /// A line made of up to three spaces then three or more backticks (or tildes). A backtick fence's info string
    /// cannot contain a backtick, so ```` ```x``` ```` on one line is inline code, not a fence.
    private static func fenceMarker(in text: NSString, content: NSRange) -> (marker: unichar, count: Int, hasInfo: Bool)? {
        var index = content.location
        let end = NSMaxRange(content)
        var spaces = 0
        while index < end, text.character(at: index) == 0x20, spaces < 3 { index += 1; spaces += 1 }
        guard index < end else { return nil }
        let marker = text.character(at: index)
        guard marker == 0x60 || marker == 0x7E else { return nil }
        var count = 0
        while index < end, text.character(at: index) == marker { index += 1; count += 1 }
        guard count >= 3 else { return nil }
        var hasInfo = false
        while index < end {
            let unit = text.character(at: index)
            if unit == 0x60 && marker == 0x60 { return nil }
            if unit != 0x20 && unit != 0x09 { hasInfo = true }
            index += 1
        }
        return (marker, count, hasInfo)
    }

    private static func styleFence(_ info: LineInfo, in storage: NSTextStorage) {
        storage.addAttributes([
            fenceKey: true,
            .font: NSFont.monospacedSystemFont(ofSize: baseSize * 0.92, weight: .regular),
            .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08)
        ], range: info.line)
        if info.kind == .fenceDelimiter { dim(info.content, in: storage) }
    }

    // MARK: Line styling

    /// A line's range without its trailing newline characters.
    private static func contentRange(of line: NSRange, in text: NSString) -> NSRange {
        var length = line.length
        while length > 0 {
            let unit = text.character(at: line.location + length - 1)
            guard unit == 0x0A || unit == 0x0D else { break }
            length -= 1
        }
        return NSRange(location: line.location, length: length)
    }

    /// CommonMark's escapable characters: ASCII punctuation.
    private static func isEscapable(_ unit: unichar) -> Bool {
        (0x21...0x2F).contains(unit) || (0x3A...0x40).contains(unit) || (0x5B...0x60).contains(unit) || (0x7B...0x7E).contains(unit)
    }

    /// The line with every `\x` escape pair replaced by two plain letters (same length), so no pattern can see an escaped
    /// marker; plus the pairs' ranges relative to the line.
    private static func maskEscapes(in line: NSString) -> (masked: String, escapes: [NSRange]) {
        var units = [unichar](repeating: 0, count: line.length)
        line.getCharacters(&units, range: NSRange(location: 0, length: line.length))
        var escapes: [NSRange] = []
        var index = 0
        while index + 1 < units.count {
            if units[index] == 0x5C, isEscapable(units[index + 1]) {
                units[index] = 0x78
                units[index + 1] = 0x78
                escapes.append(NSRange(location: index, length: 2))
                index += 2
            } else {
                index += 1
            }
        }
        return (NSString(characters: units, length: units.count) as String, escapes)
    }

    private static func style(line: NSRange, in storage: NSTextStorage, text: NSString) {
        guard line.length > 0 else { return }
        var inlineSize = baseSize

        // Patterns run on the masked line (relative offsets); `absolute` maps a result back into the storage.
        let (masked, escapes) = maskEscapes(in: text.substring(with: line) as NSString)
        let whole = NSRange(location: 0, length: (masked as NSString).length)
        func absolute(_ range: NSRange) -> NSRange { NSRange(location: range.location + line.location, length: range.length) }

        if let match = headingPattern.firstMatch(in: masked, options: [.anchored], range: whole) {
            let level = match.range(at: 1).length
            inlineSize = level == 1 ? 25 : (level == 2 ? 20 : 17)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: inlineSize, weight: .bold), range: line)
            dim(absolute(match.range), in: storage)
        } else if let match = listPattern.firstMatch(in: masked, options: [.anchored], range: whole) {
            storage.addAttributes([
                .foregroundColor: NSColor.controlAccentColor,
                .font: NSFont.systemFont(ofSize: baseSize, weight: .bold)
            ], range: absolute(match.range(at: 1)))
        } else if let match = orderedListPattern.firstMatch(in: masked, options: [.anchored], range: whole) {
            storage.addAttributes([
                .foregroundColor: NSColor.controlAccentColor,
                .font: NSFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .bold)
            ], range: absolute(match.range(at: 1)))
        } else if let match = quotePattern.firstMatch(in: masked, options: [.anchored], range: whole) {
            let paragraph = baseParagraphStyle()
            paragraph.headIndent = 14
            storage.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ], range: line)
            dim(absolute(match.range), in: storage)
        }

        // Code first: its spans are opaque to bold and italic (and to escape dimming).
        var blocked: [NSRange] = []
        var codeSpans: [NSRange] = []
        for match in codePattern.matches(in: masked, options: [], range: whole) {
            let span = absolute(match.range)
            codeSpans.append(span)
            blocked.append(span)
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: inlineSize * 0.92, weight: .regular),
                .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08)
            ], range: span)
            dim(NSRange(location: span.location, length: 1), in: storage)
            dim(NSRange(location: NSMaxRange(span) - 1, length: 1), in: storage)
        }

        func isFree(_ range: NSRange) -> Bool {
            !blocked.contains { NSIntersectionRange($0, range).length > 0 }
        }

        // Bold + italic first, so `***x***` is not read as a bold span with a stray star.
        for match in boldItalicPattern.matches(in: masked, options: [], range: whole) where isFree(absolute(match.range)) {
            let span = absolute(match.range)
            blocked.append(span)
            addTrait(.boldFontMask, in: span, storage: storage)
            addTrait(.italicFontMask, in: span, storage: storage)
            dim(NSRange(location: span.location, length: 3), in: storage)
            dim(NSRange(location: NSMaxRange(span) - 3, length: 3), in: storage)
        }

        for match in boldPattern.matches(in: masked, options: [], range: whole) where isFree(absolute(match.range)) {
            let span = absolute(match.range)
            addTrait(.boldFontMask, in: span, storage: storage)
            dim(NSRange(location: span.location, length: 2), in: storage)
            dim(NSRange(location: NSMaxRange(span) - 2, length: 2), in: storage)
        }

        for match in italicPattern.matches(in: masked, options: [], range: whole) where isFree(absolute(match.range)) {
            let span = absolute(match.range)
            addTrait(.italicFontMask, in: span, storage: storage)
            dim(NSRange(location: span.location, length: 1), in: storage)
            dim(NSRange(location: NSMaxRange(span) - 1, length: 1), in: storage)
        }

        // The backslash of each escape is dimmed like a marker; the escaped character renders as plain text.
        for escape in escapes where !codeSpans.contains(where: { NSIntersectionRange($0, absolute(escape)).length > 0 }) {
            dim(NSRange(location: absolute(escape).location, length: 1), in: storage)
        }
    }

    private static func dim(_ range: NSRange, in storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
    }

    /// Adds a font trait to every font run in `range`, keeping each run's size (so bold inside a heading
    /// stays heading-sized). Runs are collected first because the storage is modified afterwards.
    private static func addTrait(_ trait: NSFontTraitMask, in range: NSRange, storage: NSTextStorage) {
        var runs: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: range, options: []) { value, runRange, _ in
            if let font = value as? NSFont { runs.append((runRange, font)) }
        }
        for (runRange, font) in runs {
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: runRange)
        }
    }
}
