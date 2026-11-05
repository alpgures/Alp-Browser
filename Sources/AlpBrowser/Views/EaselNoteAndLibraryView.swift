//
//  EaselNoteAndLibraryView.swift
//  Alp Browser
//
//  Freeform Canvas, Notes editor, and Library Sheet views.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI

// MARK: - 1. Canvas Freeform Visual Board

public struct CanvasBoardView: View {
    @EnvironmentObject var browserState: BrowserState
    public let canvasID: UUID

    private var canvasIndex: Int? {
        browserState.canvases.firstIndex(where: { $0.id == canvasID })
    }

    public init(canvasID: UUID) {
        self.canvasID = canvasID
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Dotted grid canvas background
            Canvas { context, size in
                let step: CGFloat = 24
                for x in stride(from: step, to: size.width, by: step) {
                    for y in stride(from: step, to: size.height, by: step) {
                        let rect = CGRect(x: x, y: y, width: 1.8, height: 1.8)
                        context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.20)))
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))

            if let idx = canvasIndex {
                ForEach(browserState.canvases[idx].elements) { element in
                    CanvasCardItemView(
                        element: element,
                        onUpdate: { updated in
                            if let eIdx = browserState.canvases[idx].elements.firstIndex(where: { $0.id == updated.id }) {
                                browserState.canvases[idx].elements[eIdx] = updated
                                browserState.canvases[idx].updatedAt = Date()
                                browserState.scheduleSave()
                            }
                        },
                        onDelete: {
                            browserState.canvases[idx].elements.removeAll { $0.id == element.id }
                            browserState.scheduleSave()
                        }
                    )
                }

                // Floating Bottom Toolbar
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text(browserState.canvases[idx].title)
                            .font(.system(size: 13, weight: .bold))
                            .padding(.trailing, 6)

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
                Text("Canvas not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func pickImageFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Select Image for Canvas"
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            addImageElement(from: url)
        }
    }

    private func addImageElement(from fileURL: URL) {
        guard let idx = canvasIndex else { return }
        let count = Double(browserState.canvases[idx].elements.count)
        let el = AlpCanvasElement(
            kind: .image,
            text: fileURL.lastPathComponent,
            urlString: fileURL.path,
            x: 120 + (count * 28).truncatingRemainder(dividingBy: 380),
            y: 120 + (count * 24).truncatingRemainder(dividingBy: 260),
            width: 260,
            height: 200,
            color: RGBAColor(red: 0.15, green: 0.15, blue: 0.18)
        )
        browserState.canvases[idx].elements.append(el)
        browserState.scheduleSave()
    }

    private func addElement(kind: AlpCanvasElementKind, text: String, color: RGBAColor) {
        guard let idx = canvasIndex else { return }
        let count = Double(browserState.canvases[idx].elements.count)
        let el = AlpCanvasElement(
            kind: kind,
            text: text,
            x: 120 + (count * 28).truncatingRemainder(dividingBy: 380),
            y: 120 + (count * 24).truncatingRemainder(dividingBy: 260),
            width: kind == .textHeader ? 320 : 250,
            height: kind == .textHeader ? 68 : 160,
            color: color
        )
        browserState.canvases[idx].elements.append(el)
        browserState.scheduleSave()
    }
}

struct CanvasCardItemView: View {
    let element: AlpCanvasElement
    let onUpdate: (AlpCanvasElement) -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var draftText: String = ""
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 8, height: 8)
                Spacer()
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            if element.kind == .image, let path = element.urlString, let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                TextEditor(text: $draftText)
                    .scrollContentBackground(.hidden)
                    .font(
                        element.kind == .textHeader
                            ? .system(size: 20, weight: .bold, design: .rounded)
                            : (element.kind == .codeSnippet ? .system(size: 12, design: .monospaced) : .system(size: 13.5, weight: .medium))
                    )
                    .foregroundStyle(element.color.luminance > 0.55 ? Color.black.opacity(0.86) : Color.white.opacity(0.94))
                    .onChange(of: draftText) { _, newVal in
                        var updated = element
                        updated.text = newVal
                        onUpdate(updated)
                    }
            }
        }
        .padding(12)
        .frame(width: element.width, height: element.height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(element.color.swiftUIColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .offset(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    var updated = element
                    updated.x += value.translation.width
                    updated.y += value.translation.height
                    dragOffset = .zero
                    onUpdate(updated)
                }
        )
        .onHover { isHovered = $0 }
        .onAppear {
            draftText = element.text
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

    public init(noteID: UUID) {
        self.noteID = noteID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Note Title", text: $draftTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .onChange(of: draftTitle) { _, newVal in
                        guard let idx = noteIndex else { return }
                        browserState.notes[idx].title = newVal
                        browserState.notes[idx].updatedAt = Date()
                        browserState.scheduleSave()
                    }

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
                    formatButton(title: "B", symbol: "bold", wrap: "**")
                    formatButton(title: "I", symbol: "italic", wrap: "*")
                    formatButton(title: "H1", symbol: "number", prefix: "# ")
                    formatButton(title: "H2", symbol: "number", prefix: "## ")
                    formatButton(title: "Code", symbol: "chevron.left.forwardslash.chevron.right", wrap: "`")
                    formatButton(title: "List", symbol: "list.bullet", prefix: "- ")
                    formatButton(title: "Quote", symbol: "quote.opening", prefix: "> ")
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
                TextEditor(text: $draftBody)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .padding(.horizontal, 36)
                    .scrollContentBackground(.hidden)
                    .onChange(of: draftBody) { _, newVal in
                        guard let idx = noteIndex else { return }
                        browserState.notes[idx].body = newVal
                        browserState.notes[idx].updatedAt = Date()
                        browserState.scheduleSave()
                    }
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
    }

    private func formatButton(title: String, symbol: String, wrap: String = "", prefix: String = "") -> some View {
        Button {
            if !wrap.isEmpty {
                draftBody.append("\(wrap)text\(wrap)")
            } else if !prefix.isEmpty {
                draftBody.append("\n\(prefix)")
            }
            guard let idx = noteIndex else { return }
            browserState.notes[idx].body = draftBody
            browserState.notes[idx].updatedAt = Date()
            browserState.scheduleSave()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .frame(minWidth: 24, minHeight: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - 3. Library Drawer View (Side-Reveal Panel)

public struct LibraryDrawerView: View {
    @EnvironmentObject var browserState: BrowserState

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with tabs and close button
            HStack(spacing: 12) {
                Text("Library")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                ForEach(BrowserState.LibrarySection.allCases) { section in
                    Button {
                        browserState.selectedLibrarySection = section
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: section.icon)
                            Text(section.rawValue)
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.system(size: 11.5, weight: browserState.selectedLibrarySection == section ? .semibold : .medium))
                        .foregroundStyle(browserState.selectedLibrarySection == section ? .white : .white.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            browserState.selectedLibrarySection == section ? Color.white.opacity(0.18) : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        browserState.isLibrarySheetPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Close Library (Esc)")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))

            Divider().background(Color.white.opacity(0.12))

            // Tab Content
            Group {
                switch browserState.selectedLibrarySection {
                case .archive:
                    archiveListView
                case .canvas:
                    canvasListView
                case .notes:
                    notesListView
                case .styles:
                    stylesListView
                case .sync:
                    syncStatusView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var archiveListView: some View {
        List {
            if browserState.archivedTabs.isEmpty {
                Text("No archived tabs yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(browserState.archivedTabs) { tab in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tab.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.urlString)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(tab.reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Restore") {
                            browserState.openNewTab(urlString: tab.urlString, title: tab.title)
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                                browserState.isLibrarySheetPresented = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var canvasListView: some View {
        List {
            ForEach(browserState.canvases) { canvas in
                HStack {
                    Image(systemName: "scribble.variable")
                    Text(canvas.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Open") {
                        browserState.openNewTab(urlString: "alp://canvas/\(canvas.id)", title: canvas.title, kind: .canvas(canvas.id))
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            browserState.isLibrarySheetPresented = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var notesListView: some View {
        List {
            ForEach(browserState.notes) { note in
                HStack {
                    Image(systemName: "note.text")
                    Text(note.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Open") {
                        browserState.openNewTab(urlString: "alp://note/\(note.id)", title: note.title, kind: .note(note.id))
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            browserState.isLibrarySheetPresented = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var stylesListView: some View {
        List {
            ForEach(browserState.styles) { style in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.domain)
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(style.zappedSelectors.count) hidden elements")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { style.isEnabled },
                        set: { newVal in
                            if let idx = browserState.styles.firstIndex(where: { $0.id == style.id }) {
                                browserState.styles[idx].isEnabled = newVal
                                browserState.scheduleSave()
                            }
                        }
                    ))
                }
            }
        }
    }

    private var syncStatusView: some View {
        VStack(spacing: 16) {
            Image(systemName: browserState.isSyncConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(browserState.isSyncConnected ? Color.green : Color.orange)

            Text("Encrypted Vault Sync")
                .font(.system(size: 16, weight: .bold))

            Text("Your spaces, tabs, and styles are encrypted on your Mac before syncing.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack {
                Text("Status: \(browserState.syncStatusText)")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Sync Now") {
                    Task {
                        await browserState.syncNow()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 360)
            .padding()
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - 4. Legacy Library Sheet View (For modal compatibility)

public struct LibrarySheetView: View {
    @EnvironmentObject var browserState: BrowserState
    @Environment(\.dismiss) var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with tabs
            HStack(spacing: 12) {
                ForEach(BrowserState.LibrarySection.allCases) { section in
                    Button {
                        browserState.selectedLibrarySection = section
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: section.icon)
                            Text(section.rawValue)
                        }
                        .font(.system(size: 13, weight: browserState.selectedLibrarySection == section ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            browserState.selectedLibrarySection == section ? Color.accentColor.opacity(0.2) : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)

            Divider()

            // Tab Content
            Group {
                switch browserState.selectedLibrarySection {
                case .archive:
                    archiveListView
                case .canvas:
                    canvasListView
                case .notes:
                    notesListView
                case .styles:
                    stylesListView
                case .sync:
                    syncStatusView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    private var archiveListView: some View {
        List {
            if browserState.archivedTabs.isEmpty {
                Text("No archived tabs yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(browserState.archivedTabs) { tab in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tab.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.urlString)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(tab.reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Restore") {
                            browserState.openNewTab(urlString: tab.urlString, title: tab.title)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var canvasListView: some View {
        List {
            ForEach(browserState.canvases) { canvas in
                HStack {
                    Image(systemName: "scribble.variable")
                    Text(canvas.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Open") {
                        browserState.openNewTab(urlString: "alp://canvas/\(canvas.id)", title: canvas.title, kind: .canvas(canvas.id))
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var notesListView: some View {
        List {
            ForEach(browserState.notes) { note in
                HStack {
                    Image(systemName: "note.text")
                    Text(note.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Open") {
                        browserState.openNewTab(urlString: "alp://note/\(note.id)", title: note.title, kind: .note(note.id))
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var stylesListView: some View {
        List {
            ForEach(browserState.styles) { style in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.domain)
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(style.zappedSelectors.count) hidden elements")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { style.isEnabled },
                        set: { newVal in
                            if let idx = browserState.styles.firstIndex(where: { $0.id == style.id }) {
                                browserState.styles[idx].isEnabled = newVal
                                browserState.scheduleSave()
                            }
                        }
                    ))
                }
            }
        }
    }

    private var syncStatusView: some View {
        VStack(spacing: 16) {
            Image(systemName: browserState.isSyncConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(browserState.isSyncConnected ? Color.green : Color.orange)

            Text("Encrypted Vault Sync")
                .font(.system(size: 16, weight: .bold))

            Text("Your spaces, tabs, and styles are encrypted on your Mac before syncing.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack {
                Text("Status: \(browserState.syncStatusText)")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Sync Now") {
                    Task {
                        await browserState.syncNow()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 360)
            .padding()
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
