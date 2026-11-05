import SwiftUI

// MARK: - 1. Arc Easel Freeform Canvas View

public struct EaselCanvasView: View {
    @EnvironmentObject var browserState: BrowserState
    public let easelID: UUID

    private var easelIndex: Int? {
        browserState.easels.firstIndex(where: { $0.id == easelID })
    }

    public init(easelID: UUID) {
        self.easelID = easelID
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Dotted grid canvas background
            Canvas { context, size in
                let step: CGFloat = 24
                for x in stride(from: step, to: size.width, by: step) {
                    for y in stride(from: step, to: size.height, by: step) {
                        let rect = CGRect(x: x, y: y, width: 1.8, height: 1.8)
                        context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.22)))
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))

            if let idx = easelIndex {
                ForEach(browserState.easels[idx].elements) { element in
                    EaselCardItemView(
                        element: element,
                        onUpdate: { updated in
                            if let eIdx = browserState.easels[idx].elements.firstIndex(where: { $0.id == updated.id }) {
                                browserState.easels[idx].elements[eIdx] = updated
                                browserState.easels[idx].updatedAt = Date()
                                browserState.scheduleSave()
                            }
                        },
                        onDelete: {
                            browserState.easels[idx].elements.removeAll { $0.id == element.id }
                            browserState.scheduleSave()
                        }
                    )
                }

                // Floating Bottom Easel Toolbar
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text(browserState.easels[idx].title)
                            .font(.system(size: 13, weight: .bold))
                            .padding(.trailing, 6)

                        Button {
                            addElement(kind: .stickyNote, text: "New sticky thought...", color: RGBAColor(red: 0.99, green: 0.91, blue: 0.52))
                        } label: {
                            Label("Sticky Card", systemImage: "note")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            addElement(kind: .textHeader, text: "Section Heading", color: browserState.activeTheme.accentColor)
                        } label: {
                            Label("Heading", systemImage: "textformat.size")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            addElement(kind: .codeSnippet, text: "// Code or command snippet\nssh oci-box", color: RGBAColor(red: 0.22, green: 0.24, blue: 0.30))
                        } label: {
                            Label("Code Block", systemImage: "chevron.left.forwardslash.chevron.right")
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
    }

    private func addElement(kind: EaselElementKind, text: String, color: RGBAColor) {
        guard let idx = easelIndex else { return }
        let count = Double(browserState.easels[idx].elements.count)
        let el = EaselElement(
            kind: kind,
            text: text,
            x: 120 + (count * 28).truncatingRemainder(dividingBy: 380),
            y: 120 + (count * 24).truncatingRemainder(dividingBy: 260),
            width: kind == .textHeader ? 320 : 250,
            height: kind == .textHeader ? 68 : 160,
            color: color
        )
        browserState.easels[idx].elements.append(el)
        browserState.scheduleSave()
    }
}

struct EaselCardItemView: View {
    let element: EaselElement
    let onUpdate: (EaselElement) -> Void
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
        .padding(12)
        .frame(width: element.width, height: element.height)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(element.color.swiftUIColor)
                .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .position(
            x: element.x + element.width / 2 + dragOffset.width,
            y: element.y + element.height / 2 + dragOffset.height
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    var updated = element
                    updated.x = max(16, element.x + value.translation.width)
                    updated.y = max(16, element.y + value.translation.height)
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

// MARK: - 2. Arc Note Editor View

public struct NoteEditorView: View {
    @EnvironmentObject var browserState: BrowserState
    public let noteID: UUID

    @State private var titleDraft: String = ""
    @State private var bodyDraft: String = ""

    private var noteIndex: Int? {
        browserState.notes.firstIndex(where: { $0.id == noteID })
    }

    public init(noteID: UUID) {
        self.noteID = noteID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let idx = noteIndex {
                HStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(browserState.activeTheme.primaryColor.swiftUIColor)

                    TextField("Note Title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .onChange(of: titleDraft) { _, newTitle in
                            browserState.notes[idx].title = newTitle
                            browserState.notes[idx].updatedAt = Date()
                            if let activeID = browserState.activeTabID {
                                browserState.mutateTab(id: activeID) { $0.title = "📝 \(newTitle)" }
                            }
                            browserState.scheduleSave()
                        }

                    Spacer()

                    Text("Synced with OCI Cloud")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 28)
                .padding(.horizontal, 48)

                Divider()
                    .padding(.horizontal, 48)

                TextEditor(text: $bodyDraft)
                    .font(.system(size: 15, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 44)
                    .padding(.bottom, 28)
                    .onChange(of: bodyDraft) { _, newBody in
                        browserState.notes[idx].body = newBody
                        browserState.notes[idx].updatedAt = Date()
                        browserState.scheduleSave()
                    }
                    .onAppear {
                        titleDraft = browserState.notes[idx].title
                        bodyDraft = browserState.notes[idx].body
                    }
            } else {
                Text("Note not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - 3. Arc Library & OCI Cloud Sync Sheet

public struct LibrarySheetView: View {
    @EnvironmentObject var browserState: BrowserState

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar inside Library
            VStack(alignment: .leading, spacing: 6) {
                Text("Arc Library")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                ForEach(BrowserState.LibrarySection.allCases) { section in
                    let isSelected = browserState.selectedLibrarySection == section
                    Button {
                        browserState.selectedLibrarySection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .frame(width: 18)
                            Text(section.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? browserState.activeTheme.primaryColor.swiftUIColor.opacity(0.25) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    browserState.importFromInstalledArcBrowser()
                } label: {
                    Label("Import from Arc.app", systemImage: "arrow.down.doc.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(browserState.activeTheme.primaryColor.swiftUIColor)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .frame(width: 190)
            .padding(10)
            .background(Color.black.opacity(0.14))

            Divider()

            // Right Detail Area
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(browserState.selectedLibrarySection.rawValue)
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button("Done") {
                        browserState.isLibrarySheetPresented = false
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                switch browserState.selectedLibrarySection {
                case .archive:
                    archiveSectionView
                case .easels:
                    easelsSectionView
                case .notes:
                    notesSectionView
                case .boosts:
                    boostsSectionView
                case .ociCloud:
                    ociCloudSectionView
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 480)
        .background(.regularMaterial)
    }

    private var archiveSectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Auto-archived Today tabs & recently closed tabs")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if !browserState.archivedTabs.isEmpty {
                    Button("Clear Archive") {
                        browserState.archivedTabs.removeAll()
                        browserState.scheduleSave()
                    }
                    .font(.system(size: 11.5))
                }
            }

            if browserState.archivedTabs.isEmpty {
                Spacer()
                Text("No archived tabs yet. Unpinned Today tabs automatically archive after \(Int(browserState.autoArchiveHours)) hours.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(browserState.archivedTabs) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    Text("\(item.urlString) • \(item.reason)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Restore") {
                                    browserState.openNewTab(urlString: item.urlString, title: item.title)
                                    browserState.archivedTabs.removeAll { $0.id == item.id }
                                    browserState.isLibrarySheetPresented = false
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                        }
                    }
                }
            }
        }
    }

    private var easelsSectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                browserState.createNewEasel(title: "Easel #\(browserState.easels.count + 1)")
                browserState.isLibrarySheetPresented = false
            } label: {
                Label("Create New Easel", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            ScrollView {
                ForEach(browserState.easels) { easel in
                    HStack {
                        Label(easel.title, systemImage: "scribble.variable")
                            .font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Text("\(easel.elements.count) cards")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Button("Open") {
                            browserState.openNewTab(
                                urlString: "arc://easel/\(easel.id.uuidString)",
                                title: "🎨 \(easel.title)",
                                kind: .easel(easel.id)
                            )
                            browserState.isLibrarySheetPresented = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
            }
        }
    }

    private var notesSectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                browserState.createNewNote(title: "Note #\(browserState.notes.count + 1)")
                browserState.isLibrarySheetPresented = false
            } label: {
                Label("Create New Note", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            ScrollView {
                ForEach(browserState.notes) { note in
                    HStack {
                        Label(note.title, systemImage: "note.text")
                            .font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Button("Open") {
                            browserState.openNewTab(
                                urlString: "arc://note/\(note.id.uuidString)",
                                title: "📝 \(note.title)",
                                kind: .note(note.id)
                            )
                            browserState.isLibrarySheetPresented = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
            }
        }
    }

    private var boostsSectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if browserState.boosts.isEmpty {
                    Text("No site Boosts created yet. Click the lightning bolt ⚡ in the sidebar URL pill on any website to create one.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }
                ForEach(browserState.boosts) { boost in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(boost.domain)
                                .font(.system(size: 13.5, weight: .bold))
                            Text("\(boost.zappedSelectors.count) zapped elements • Hue \(Int(boost.hueRotateDegrees))°")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Delete") {
                            browserState.boosts.removeAll { $0.id == boost.id }
                            browserState.scheduleSave()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
            }
        }
    }

    private var ociCloudSectionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(browserState.ociConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(browserState.ociStatusText)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Test Connection") {
                    Task { await browserState.refreshOCIConnectionStatus() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))

            HStack {
                Text("SSH Host Alias:")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 140, alignment: .leading)
                TextField("oci-box", text: $browserState.ociConfig.sshHostAlias)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await browserState.syncToOCICloudNow() }
                } label: {
                    Label("Backup All Spaces, Tabs & Easels to OCI Box Now", systemImage: "icloud.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await browserState.restoreFromOCICloudNow() }
                } label: {
                    Label("Restore from OCI Box", systemImage: "icloud.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Text("Featherweight Memory & Auto-Archive Settings")
                .font(.system(size: 13, weight: .bold))

            HStack {
                Text("Auto-Hibernate Inactive Tabs After:")
                    .font(.system(size: 12))
                Slider(value: $browserState.autoHibernateMinutes, in: 1...30, step: 1)
                Text("\(Int(browserState.autoHibernateMinutes)) min")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 55)
            }

            HStack {
                Text("Auto-Archive Today Tabs After:")
                    .font(.system(size: 12))
                Slider(value: $browserState.autoArchiveHours, in: 1...48, step: 1)
                Text("\(Int(browserState.autoArchiveHours)) hrs")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 55)
            }

            Toggle("Native WebKit Bytecode Ad & Tracker Blocker (Zero-RAM)", isOn: $browserState.adBlockerEnabled)
                .font(.system(size: 12))
        }
    }
}
