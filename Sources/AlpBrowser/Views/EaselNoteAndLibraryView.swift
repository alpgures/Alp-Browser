//
//  EaselNoteAndLibraryView.swift
//  Alp Browser
//
//  Freeform easel board and note editor tab views.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Edits typed into cards and notes are written to the store after a short pause rather than per keystroke,
/// because every store mutation re-renders everything observing `BrowserState`.
private let editCommitDelayNanos: UInt64 = 350_000_000

// MARK: - 1. Easel Freeform Visual Board

public struct CanvasBoardView: View {
    @EnvironmentObject var browserState: BrowserState
    public let canvasID: UUID

    @State private var draftTitle: String = ""
    @State private var pendingTitleTask: Task<Void, Never>?

    private var canvasIndex: Int? {
        browserState.canvases.firstIndex(where: { $0.id == canvasID })
    }

    public init(canvasID: UUID) {
        self.canvasID = canvasID
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Dotted grid canvas background (rasterised once; it does not depend on the cards)
            Canvas { context, size in
                let step: CGFloat = 24
                for x in stride(from: step, to: size.width, by: step) {
                    for y in stride(from: step, to: size.height, by: step) {
                        let rect = CGRect(x: x, y: y, width: 1.8, height: 1.8)
                        context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.20)))
                    }
                }
            }
            .drawingGroup()
            .background(Color(nsColor: .windowBackgroundColor))

            if let idx = canvasIndex {
                ForEach(browserState.canvases[idx].elements) { element in
                    CanvasCardItemView(
                        element: element,
                        onMutate: { transform in mutateElement(id: element.id, transform) },
                        onBringToFront: { bringToFront(id: element.id) },
                        onDelete: { deleteElement(id: element.id) },
                        onOpenLink: { link in
                            browserState.openNewTab(urlString: link)
                        }
                    )
                }

                // Floating Bottom Toolbar
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        TextField("Easel name", text: $draftTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 130)
                            .onChange(of: draftTitle) { _, newVal in scheduleRename(newVal) }

                        Button {
                            addElement(kind: .stickyNote, text: "New sticky note...", color: RGBAColor(red: 0.99, green: 0.91, blue: 0.52))
                        } label: {
                            Label("Sticky Note", systemImage: "note")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            addElement(kind: .textHeader, text: "Heading", color: browserState.activeTheme.accentColor)
                        } label: {
                            Label("Heading", systemImage: "textformat.size")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            addElement(kind: .codeSnippet, text: "// Code or command snippet", color: RGBAColor(red: 0.22, green: 0.24, blue: 0.30))
                        } label: {
                            Label("Code Block", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            addLinkFromClipboard()
                        } label: {
                            Label("Link", systemImage: "link")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            pickImageFromDisk()
                        } label: {
                            Label("Image", systemImage: "photo")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                    .padding(.bottom, 22)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Easel not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if let idx = canvasIndex { draftTitle = browserState.canvases[idx].title }
        }
        .onDisappear {
            pendingTitleTask?.cancel()
            if let idx = canvasIndex, browserState.canvases[idx].title != draftTitle {
                browserState.renameCanvas(id: canvasID, to: draftTitle)
            }
        }
    }

    private func scheduleRename(_ title: String) {
        pendingTitleTask?.cancel()
        let id = canvasID
        pendingTitleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: editCommitDelayNanos)
            guard !Task.isCancelled else { return }
            browserState.renameCanvas(id: id, to: title)
        }
    }

    // MARK: Element operations (always looked up by id so stale closures never write to the wrong slot)

    private func mutateElement(id: UUID, _ transform: (inout AlpCanvasElement) -> Void) {
        guard let cIdx = canvasIndex,
              let eIdx = browserState.canvases[cIdx].elements.firstIndex(where: { $0.id == id }) else { return }
        transform(&browserState.canvases[cIdx].elements[eIdx])
        browserState.canvases[cIdx].updatedAt = Date()
        browserState.scheduleSave()
    }

    private func bringToFront(id: UUID) {
        guard let cIdx = canvasIndex,
              let eIdx = browserState.canvases[cIdx].elements.firstIndex(where: { $0.id == id }),
              eIdx != browserState.canvases[cIdx].elements.count - 1 else { return }
        let element = browserState.canvases[cIdx].elements.remove(at: eIdx)
        browserState.canvases[cIdx].elements.append(element)
        browserState.scheduleSave()
    }

    private func deleteElement(id: UUID) {
        guard let cIdx = canvasIndex else { return }
        browserState.canvases[cIdx].elements.removeAll { $0.id == id }
        browserState.canvases[cIdx].updatedAt = Date()
        browserState.scheduleSave()
    }

    private func nextOrigin() -> (x: Double, y: Double) {
        let count = Double(canvasIndex.map { browserState.canvases[$0].elements.count } ?? 0)
        return (120 + (count * 28).truncatingRemainder(dividingBy: 380),
                120 + (count * 24).truncatingRemainder(dividingBy: 260))
    }

    private func append(_ element: AlpCanvasElement) {
        guard let idx = canvasIndex else { return }
        browserState.canvases[idx].elements.append(element)
        browserState.canvases[idx].updatedAt = Date()
        browserState.scheduleSave()
    }

    private func pickImageFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Select Image for Easel"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            // Copy into the app's own storage so the card survives the original file moving.
            guard let storedPath = BrowserState.importCanvasImage(from: url) else {
                browserState.showToast("Could not add that image")
                return
            }
            let origin = nextOrigin()
            append(AlpCanvasElement(
                kind: .image,
                text: url.lastPathComponent,
                urlString: storedPath,
                x: origin.x,
                y: origin.y,
                width: 260,
                height: 200,
                color: RGBAColor(red: 0.15, green: 0.15, blue: 0.18)
            ))
        }
    }

    private func addLinkFromClipboard() {
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: clip), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            browserState.showToast("Copy a link first, then add it to the easel")
            return
        }
        let origin = nextOrigin()
        append(AlpCanvasElement(
            kind: .webCard,
            text: "\(url.host ?? clip)\n\(clip)",
            urlString: clip,
            x: origin.x,
            y: origin.y,
            width: 280,
            height: 100,
            color: browserState.activeTheme.primaryColor
        ))
    }

    private func addElement(kind: AlpCanvasElementKind, text: String, color: RGBAColor) {
        let origin = nextOrigin()
        append(AlpCanvasElement(
            kind: kind,
            text: text,
            x: origin.x,
            y: origin.y,
            width: kind == .textHeader ? 320 : 250,
            height: kind == .textHeader ? 68 : 160,
            color: color
        ))
    }
}

struct CanvasCardItemView: View {
    let element: AlpCanvasElement
    let onMutate: ((inout AlpCanvasElement) -> Void) -> Void
    let onBringToFront: () -> Void
    let onDelete: () -> Void
    let onOpenLink: (String) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero
    @State private var draftText: String = ""
    @State private var pendingTextTask: Task<Void, Never>?
    @State private var isHovered = false
    /// Decoded once per card instead of on every body evaluation (which runs during drags).
    @State private var loadedImage: NSImage?

    private static let palette: [(name: String, color: RGBAColor)] = [
        ("Yellow", RGBAColor(red: 0.99, green: 0.91, blue: 0.52)),
        ("Pink", RGBAColor(red: 0.98, green: 0.70, blue: 0.78)),
        ("Green", RGBAColor(red: 0.69, green: 0.90, blue: 0.70)),
        ("Blue", RGBAColor(red: 0.62, green: 0.80, blue: 0.97)),
        ("White", RGBAColor(red: 0.97, green: 0.97, blue: 0.97)),
        ("Graphite", RGBAColor(red: 0.22, green: 0.24, blue: 0.30))
    ]

    private var cardWidth: CGFloat { max(120, CGFloat(element.width) + resizeDelta.width) }
    private var cardHeight: CGFloat { max(60, CGFloat(element.height) + resizeDelta.height) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 8, height: 8)
                Spacer()
                if isHovered {
                    if element.kind == .webCard, let link = element.urlString {
                        Button { onOpenLink(link) } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Open link in a new tab")
                    }
                    if element.kind != .image {
                        Menu {
                            ForEach(Self.palette, id: \.name) { entry in
                                Button(entry.name) {
                                    onMutate { $0.color = entry.color }
                                }
                            }
                        } label: {
                            Image(systemName: "paintpalette")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            if element.kind == .image {
                if let img = loadedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Text(element.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                TextEditor(text: $draftText)
                    .scrollContentBackground(.hidden)
                    .font(
                        element.kind == .textHeader
                            ? .system(size: 20, weight: .bold, design: .rounded)
                            : (element.kind == .codeSnippet ? .system(size: 12, design: .monospaced) : .system(size: 13.5, weight: .medium))
                    )
                    .foregroundStyle(element.color.luminance > 0.55 ? Color.black.opacity(0.86) : Color.white.opacity(0.94))
                    .onChange(of: draftText) { _, newVal in scheduleTextCommit(newVal) }
            }
        }
        .padding(12)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(element.color.swiftUIColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            // Resize handle
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary.opacity(isHovered ? 0.55 : 0))
                .padding(6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in resizeDelta = value.translation }
                        .onEnded { value in
                            let delta = value.translation
                            resizeDelta = .zero
                            onMutate {
                                $0.width = max(120, $0.width + Double(delta.width))
                                $0.height = max(60, $0.height + Double(delta.height))
                            }
                        }
                )
        }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .offset(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let delta = value.translation
                    dragOffset = .zero
                    onMutate {
                        $0.x += Double(delta.width)
                        $0.y += Double(delta.height)
                    }
                    onBringToFront()
                }
        )
        .onHover { isHovered = $0 }
        .onAppear {
            draftText = element.text
            if element.kind == .image, loadedImage == nil, let path = element.urlString {
                loadedImage = NSImage(contentsOfFile: path)
            }
        }
        .onDisappear {
            // Flush an edit still waiting on its pause so closing the tab never drops text.
            pendingTextTask?.cancel()
            if element.kind != .image, draftText != element.text {
                let text = draftText
                onMutate { $0.text = text }
            }
        }
    }

    private func scheduleTextCommit(_ text: String) {
        pendingTextTask?.cancel()
        pendingTextTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: editCommitDelayNanos)
            guard !Task.isCancelled else { return }
            onMutate { $0.text = text }
        }
    }
}

// MARK: - 2. Distraction-Free Note Editor

public struct NoteEditorView: View {
    @EnvironmentObject var browserState: BrowserState
    public let noteID: UUID

    private var noteIndex: Int? {
        browserState.notes.firstIndex(where: { $0.id == noteID })
    }

    @State private var draftTitle: String = ""
    @State private var draftBody: String = ""
    @State private var isPreviewMode: Bool = false
    @State private var pendingTitleTask: Task<Void, Never>?
    @State private var pendingBodyTask: Task<Void, Never>?
    @StateObject private var textController = NoteTextController()

    public init(noteID: UUID) {
        self.noteID = noteID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Note Title", text: $draftTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .onChange(of: draftTitle) { _, _ in scheduleTitleCommit() }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isPreviewMode.toggle()
                    }
                } label: {
                    Label(isPreviewMode ? "Edit" : "Preview", systemImage: isPreviewMode ? "pencil" : "eye")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)

            // Markdown Quick-Formatting Toolbar
            if !isPreviewMode {
                HStack(spacing: 8) {
                    formatButton(title: "B", wrap: "**")
                    formatButton(title: "I", wrap: "*")
                    formatButton(title: "H1", prefix: "# ")
                    formatButton(title: "H2", prefix: "## ")
                    formatButton(title: "Code", wrap: "`")
                    formatButton(title: "List", prefix: "- ")
                    formatButton(title: "Quote", prefix: "> ")
                    Spacer()
                }
                .padding(.horizontal, 36)
            }

            Divider()
                .padding(.horizontal, 36)

            if isPreviewMode {
                ScrollView {
                    Text(LocalizedStringKey(draftBody.isEmpty ? "*Empty note*" : draftBody))
                        .font(.system(size: 15))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.top, 8)
                }
            } else {
                NoteTextView(text: $draftBody, controller: textController)
                    .padding(.horizontal, 36)
                    .onChange(of: draftBody) { _, _ in scheduleBodyCommit() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let idx = noteIndex {
                draftTitle = browserState.notes[idx].title
                draftBody = browserState.notes[idx].body
            }
        }
        .onDisappear {
            pendingTitleTask?.cancel()
            pendingBodyTask?.cancel()
            commitTitle()
            commitBody()
        }
    }

    private func scheduleTitleCommit() {
        pendingTitleTask?.cancel()
        pendingTitleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: editCommitDelayNanos)
            guard !Task.isCancelled else { return }
            commitTitle()
        }
    }

    private func scheduleBodyCommit() {
        pendingBodyTask?.cancel()
        pendingBodyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: editCommitDelayNanos)
            guard !Task.isCancelled else { return }
            commitBody()
        }
    }

    private func commitTitle() {
        guard let idx = noteIndex, browserState.notes[idx].title != draftTitle else { return }
        browserState.renameNote(id: noteID, to: draftTitle)
    }

    private func commitBody() {
        guard let idx = noteIndex, browserState.notes[idx].body != draftBody else { return }
        browserState.notes[idx].body = draftBody
        browserState.notes[idx].updatedAt = Date()
        browserState.scheduleSave()
    }

    /// Wraps the current selection in `wrap` (or inserts a placeholder at the cursor), or toggles
    /// `prefix` on every line the selection touches.
    private func formatButton(title: String, wrap: String = "", prefix: String = "") -> some View {
        Button {
            if !wrap.isEmpty {
                textController.wrapSelection(with: wrap)
            } else if !prefix.isEmpty {
                textController.toggleLinePrefix(prefix)
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .frame(minWidth: 24, minHeight: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Selection-aware note text view

/// Applies markdown formatting to the live selection of the note's `NSTextView`.
/// `TextEditor` exposes no selection before macOS 15, so the editor is an AppKit view.
@MainActor
final class NoteTextController: ObservableObject {
    weak var textView: NSTextView?

    /// Wraps the selection in `marker` and keeps the inner text selected. With no selection it
    /// inserts `marker + placeholder + marker` at the cursor and selects the placeholder.
    func wrapSelection(with marker: String, placeholder: String = "text") {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let range = clamped(tv.selectedRange(), in: ns)
        let inner = range.length > 0 ? ns.substring(with: range) : placeholder
        let markerLength = (marker as NSString).length
        replace(range, with: marker + inner + marker, in: tv)
        tv.setSelectedRange(NSRange(location: range.location + markerLength, length: (inner as NSString).length))
        tv.window?.makeFirstResponder(tv)
    }

    /// Adds `prefix` to each line touched by the selection, or removes it when every such line
    /// already has it. With no selection the cursor's line is used.
    func toggleLinePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let selection = clamped(tv.selectedRange(), in: ns)
        let lineRange = ns.lineRange(for: selection)
        let block = ns.substring(with: lineRange)

        var lines = block.components(separatedBy: "\n")
        // A block ending in a newline splits into a trailing empty piece that is not a line.
        let hasTrailingNewline = block.hasSuffix("\n")
        if hasTrailingNewline { lines.removeLast() }

        let allPrefixed = !lines.isEmpty && lines.allSatisfy { $0.hasPrefix(prefix) }
        let transformed = lines.map { allPrefixed ? String($0.dropFirst(prefix.count)) : prefix + $0 }
        let replacement = transformed.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")

        replace(lineRange, with: replacement, in: tv)

        let delta = (replacement as NSString).length - lineRange.length
        if selection.length == 0 {
            let cursor = max(lineRange.location, selection.location + (allPrefixed ? -(prefix as NSString).length : (prefix as NSString).length))
            tv.setSelectedRange(NSRange(location: min(cursor, (tv.string as NSString).length), length: 0))
        } else {
            tv.setSelectedRange(NSRange(location: lineRange.location, length: lineRange.length + delta))
        }
        tv.window?.makeFirstResponder(tv)
    }

    /// Goes through the text view's change protocol so undo and the delegate callback both work.
    private func replace(_ range: NSRange, with string: String, in tv: NSTextView) {
        guard tv.shouldChangeText(in: range, replacementString: string) else { return }
        tv.replaceCharacters(in: range, with: string)
        tv.didChangeText()
    }

    private func clamped(_ range: NSRange, in string: NSString) -> NSRange {
        let location = min(range.location, string.length)
        return NSRange(location: location, length: min(range.length, string.length - location))
    }
}

/// Plain-text editor that maps ⌘B / ⌘I / ⌘E to the same actions as the toolbar buttons.
/// Handled in `performKeyEquivalent`, which the window offers to the view hierarchy before the
/// main menu, and only while this view is the first responder, so other windows and fields keep
/// their own shortcuts. Edits go through `NoteTextController`, so undo and the debounce are unchanged.
final class NoteNSTextView: NSTextView {
    weak var controller: NoteTextController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased(),
              let controller else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "b": controller.wrapSelection(with: "**")
        case "i": controller.wrapSelection(with: "*")
        case "e": controller.wrapSelection(with: "`")   // ⌘` is the system window-cycling key
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: NoteTextController

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        // Same setup as NSTextView.scrollableTextView(), but with our subclass as the document view.
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let tv = NoteNSTextView(frame: .zero)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = tv
        tv.controller = controller
        let paragraph = NoteMarkdownStyler.baseParagraphStyle()
        let font = NoteMarkdownStyler.baseFont

        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = font
        tv.textColor = .labelColor
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        tv.textContainerInset = NSSize(width: 0, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.string = text
        controller.textView = tv
        if let storage = tv.textStorage { NoteMarkdownStyler.restyle(storage) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        controller.textView = tv
        // Only push external changes; edits made in the view already flowed into the binding.
        if tv.string != text {
            let selection = tv.selectedRange()
            tv.string = text
            let length = (text as NSString).length
            let location = min(selection.location, length)
            tv.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            if let storage = tv.textStorage { NoteMarkdownStyler.restyle(storage) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        /// Range touched by the edit in flight, recorded before the change so only its paragraphs are restyled.
        private var pendingEdit: NSRange?

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // One extra character so a newline typed mid-line also restyles the paragraph it creates.
            pendingEdit = NSRange(location: affectedCharRange.location, length: ((replacementString as NSString?)?.length ?? 0) + 1)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Styling only touches attributes, so the stored markdown and the undo stack are unaffected.
            // Marked text (an input method mid-composition) is left alone until it is committed.
            if !tv.hasMarkedText(), let storage = tv.textStorage {
                // Without a recorded edit (undo/redo) restyle everything.
                NoteMarkdownStyler.restyle(storage, in: pendingEdit)
                tv.typingAttributes = NoteMarkdownStyler.baseAttributes
            }
            pendingEdit = nil
            guard tv.string != text.wrappedValue else { return }
            text.wrappedValue = tv.string
        }
    }
}
