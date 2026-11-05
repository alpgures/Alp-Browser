//
//  BoostEditorForm.swift
//  Alp Browser
//
//  The editing controls for one boost, shared by the page Boost panel and the Library's Boost editor.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI

/// Actions that only make sense while a page of the boost's site is open. The Library editor passes nil.
struct BoostPageActions {
    var snipElement: () -> Void
    var runScript: (String) -> Void
}

struct BoostEditorForm: View {
    @Binding var boost: PageMod
    var enabledTitle: String
    var pageActions: BoostPageActions?
    var onReset: () -> Void
    var onDelete: () -> Void

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(enabledTitle, isOn: $boost.isEnabled)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            // Element zapper trigger (only when a page of the site is open)
            if let pageActions {
                Button {
                    pageActions.snipElement()
                } label: {
                    HStack {
                        Image(systemName: "scissors")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Snip / Hide Element on Page")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if !boost.zappedSelectors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hidden elements")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach(boost.zappedSelectors, id: \.self) { selector in
                        HStack(spacing: 6) {
                            Text(selector)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                boost.zappedSelectors.removeAll { $0 == selector }
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Show this element again")
                        }
                    }
                }
            }

            VStack(spacing: 6) {
                sliderRow("Brightness", value: $boost.brightness, range: 0.5...1.5)
                sliderRow("Contrast", value: $boost.contrast, range: 0.5...1.5)
                sliderRow("Saturation", value: $boost.saturate, range: 0...2)
                sliderRow("Hue", value: $boost.hueRotateDegrees, range: -180...180)
                sliderRow("Text size", value: $boost.fontScalePercent, range: 70...160)
                Toggle("Invert Colors", isOn: $boost.invertColors)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
            }

            // Tint overlay
            HStack {
                Toggle("Color tint", isOn: Binding(
                    get: { boost.tintColor != nil },
                    set: { boost.tintColor = $0 ? RGBAColor(red: 0.4, green: 0.5, blue: 1.0) : nil }
                ))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if boost.tintColor != nil {
                    ColorPicker("", selection: Binding(
                        get: { (boost.tintColor ?? RGBAColor(red: 0.4, green: 0.5, blue: 1.0)).swiftUIColor },
                        set: { boost.tintColor = RGBAColor(color: $0) }
                    ))
                    .labelsHidden()
                }
            }

            // Font Family Override
            HStack {
                Text("Font")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Picker("", selection: Binding(
                    get: { boost.fontFamily ?? "Default" },
                    set: { boost.fontFamily = $0 == "Default" ? nil : $0 }
                )) {
                    Text("Default").tag("Default")
                    Text("Georgia").tag("Georgia")
                    Text("Menlo").tag("Menlo")
                    Text("Palatino").tag("Palatino")
                    Text("Courier").tag("Courier")
                    Text("Helvetica Neue").tag("Helvetica Neue")
                }
                .labelsHidden()
                .controlSize(.small)
            }

            codeBox(title: "Custom CSS", text: $boost.customCSS)

            VStack(alignment: .leading, spacing: 4) {
                codeBox(title: "Custom JavaScript (runs on every load of this site)", text: $boost.customJS)
                if let pageActions {
                    Button {
                        pageActions.runScript(boost.customJS)
                    } label: {
                        Label("Run on this page now", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)
                    .disabled(boost.customJS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack {
                Button("Reset") { onReset() }
                    .controlSize(.small)

                Spacer()

                Button("Delete Boost", role: .destructive) { onDelete() }
                    .controlSize(.small)
            }
        }
        .padding(.trailing, 4)
    }


    private func codeBox(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.35))
                .frame(height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 0.6))
        }
    }
}

/// Edits a saved boost from the Library, without a page of its site being open. It reads and writes the same
/// `BrowserState.styles` entry the page Boost panel uses, so there is only one boost format.
struct LibraryBoostEditorView: View {
    @EnvironmentObject var browserState: BrowserState
    @Environment(\.dismiss) private var dismiss

    let boostID: UUID
    @State private var draft: PageMod?
    /// The last value written to the store; edits equal to it are not written again.
    @State private var lastWritten: PageMod?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(draft.map { "Boost — \($0.domain)" } ?? "Boost", systemImage: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
            }

            if draft != nil {
                TextField("Name", text: Binding(
                    get: { draft?.name ?? "" },
                    set: { draft?.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

                ScrollView(.vertical, showsIndicators: false) {
                    BoostEditorForm(
                        boost: Binding(
                            get: { draft ?? PageMod(domain: "") },
                            set: { draft = $0 }
                        ),
                        enabledTitle: "Boost enabled",
                        pageActions: nil,
                        onReset: {
                            guard let current = draft else { return }
                            var fresh = PageMod(domain: current.domain, name: current.name)
                            fresh.id = current.id
                            draft = fresh
                        },
                        onDelete: {
                            browserState.deleteBoost(id: boostID)
                            dismiss()
                        }
                    )
                }
                .frame(maxHeight: 460)
            } else {
                Text("This boost no longer exists.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(red: 0.12, green: 0.12, blue: 0.15))
        .onAppear {
            let loaded = browserState.styles.first { $0.id == boostID }
            draft = loaded
            lastWritten = loaded
        }
        .onChange(of: draft) { _, newValue in
            guard var edited = newValue, edited != lastWritten,
                  let idx = browserState.styles.firstIndex(where: { $0.id == boostID }) else { return }
            lastWritten = edited
            edited.updatedAt = Date()
            browserState.styles[idx] = edited
            browserState.scheduleSave()
        }
        .onDisappear {
            // Install the finished boost as a user script on open tabs and persist it.
            browserState.commitBoostChanges()
        }
    }
}
