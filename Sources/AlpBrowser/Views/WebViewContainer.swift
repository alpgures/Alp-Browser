//
//  WebViewContainer.swift
//  Alp Browser
//
//  Native WKWebView host container and split-pane layout views.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import WebKit
import AppKit

public struct WebViewRepresentable: NSViewRepresentable {
    public let tab: TabItem
    public let isFocusedPane: Bool
    public let onFocus: () -> Void

    public init(tab: TabItem, isFocusedPane: Bool = true, onFocus: @escaping () -> Void = {}) {
        self.tab = tab
        self.isFocusedPane = isFocusedPane
        self.onFocus = onFocus
    }

    public func makeNSView(context: Context) -> NSView {
        let container = ClickTrackingContainerView()
        container.onFocusRequest = onFocus
        let wv = WebViewPool.shared.webView(for: tab)
        container.attachWebView(wv)
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? ClickTrackingContainerView else { return }
        container.onFocusRequest = onFocus
        let wv = WebViewPool.shared.webView(for: tab)
        if container.hostedWebView !== wv {
            container.attachWebView(wv)
        }
    }
}

final class ClickTrackingContainerView: NSView {
    weak var hostedWebView: WKWebView?
    var onFocusRequest: (() -> Void)?
    private var mouseMonitor: Any?

    /// WKWebView consumes mouse-downs, so the container watches for them with a local monitor
    /// (the event is passed through untouched) and asks to become the focused split pane.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) { self.onFocusRequest?() }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    deinit {
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
    }

    func attachWebView(_ webView: WKWebView) {
        subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        hostedWebView = webView
    }
}

// MARK: - Drop target for tabs dragged onto a split pane

/// Transparent AppKit layer above a split pane that accepts a tab dragged from the sidebar.
/// It exists because the pane's content (a WKWebView, a text view) registers its own drag types and would
/// otherwise take the drop itself, e.g. by inserting the tab's id as text. The layer is invisible to the
/// mouse (hit-testing returns nil) except while a sidebar tab drag is in progress with the button held.
struct PaneTabDropTarget: NSViewRepresentable {
    /// True when dropping this tab on the pane makes sense (not the pane's own tab, and it exists).
    let accepts: (UUID) -> Bool
    let onDropTab: (UUID) -> Void

    func makeNSView(context: Context) -> TabDropTargetView {
        let view = TabDropTargetView()
        view.accepts = accepts
        view.onDropTab = onDropTab
        return view
    }

    func updateNSView(_ view: TabDropTargetView, context: Context) {
        view.accepts = accepts
        view.onDropTab = onDropTab
    }
}

final class TabDropTargetView: NSView {
    var accepts: ((UUID) -> Bool)?
    var onDropTab: ((UUID) -> Void)?
    private var mouseMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
        wantsLayer = true
        layer?.cornerRadius = 11
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        guard window != nil else { return }
        // A fresh click cannot happen during a drag, so a drag id still set at mouse-down is stale
        // (the drag was cancelled). Clear it before hit-testing so the layer never blocks clicks.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            BrowserState.shared.sidebarDragTabID = nil
            return event
        }
    }

    deinit {
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
    }

    private var isTabDragActive: Bool {
        BrowserState.shared.sidebarDragTabID != nil && (NSEvent.pressedMouseButtons & 1) != 0
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isTabDragActive ? super.hitTest(point) : nil
    }

    private func draggedTabID(_ sender: NSDraggingInfo) -> UUID? {
        guard let string = sender.draggingPasteboard.string(forType: .string),
              let id = UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              accepts?(id) == true else { return nil }
        return id
    }

    private func setHighlighted(_ on: Bool) {
        layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor : nil
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = on ? 2 : 0
    }

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        let mask = sender.draggingSourceOperationMask
        for candidate in [NSDragOperation.generic, .move, .copy] where mask.contains(candidate) { return candidate }
        return []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedTabID(sender) != nil else { return [] }
        setHighlighted(true)
        return operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedTabID(sender) != nil ? operation(for: sender) : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setHighlighted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedTabID(sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHighlighted(false)
        BrowserState.shared.sidebarDragTabID = nil
        guard let id = draggedTabID(sender) else { return false }
        onDropTab?(id)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        setHighlighted(false)
    }
}

public struct ViewportPaneView: View {
    @EnvironmentObject var browserState: BrowserState

    public let tab: TabItem
    public let isSplitMode: Bool
    public let isFocusedPane: Bool

    public var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)

            switch tab.kind {
            case .web:
                if tab.isStartPage {
                    // Blank tabs never create a web view: the native page is instant and fully offline.
                    StartPageView()
                } else {
                    WebViewRepresentable(
                        tab: tab,
                        isFocusedPane: isFocusedPane,
                        onFocus: {
                            if browserState.activeTabID != tab.id {
                                browserState.activeTabID = tab.id
                            }
                        }
                    )
                }
            case .canvas(let canvasID):
                CanvasBoardView(canvasID: canvasID)
            case .note(let noteID):
                NoteEditorView(noteID: noteID)
            }

            // Top Loading Progress Bar: sits on the top edge of the page, which is already below the
            // collapsed-sidebar navigation strip, so it never overlaps the traffic lights or the URL pill.
            if tab.isLoading && tab.estimatedProgress < 1.0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    browserState.activeTheme.effectiveAccentColor,
                                    browserState.activeTheme.primaryColor.swiftUIColor
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * CGFloat(tab.estimatedProgress), 24), height: 2.5)
                        .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                }
                .frame(height: 2.5)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Trackpad Back / Forward Navigation Edge Indicator
            if isFocusedPane {
                ViewportSwipeEdgeIndicatorView(accentColor: browserState.activeTheme.primaryColor.swiftUIColor)
            }

            // Active Element Zapper Banner
            if isFocusedPane && WebViewPool.shared.isZapperModeActive {
                ViewportZapperBannerView(tabID: tab.id)
            }

            // A tab dragged from the sidebar onto this pane replaces the pane's tab, or (single viewport) starts a split.
            PaneTabDropTarget(
                accepts: { id in id != tab.id && browserState.findTab(id: id) != nil },
                onDropTab: { id in browserState.dropSidebarTab(id, onPane: tab.id) }
            )

            // Split View Mini Header
            if isSplitMode {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isFocusedPane ? browserState.activeTheme.effectiveAccentColor : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)

                    Text(tab.simplifiedDomain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)

                    Spacer()

                    Button {
                        browserState.removeSplitPane(tabID: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Remove this pane from Split View")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    isFocusedPane && isSplitMode
                        ? browserState.activeTheme.effectiveAccentColor.opacity(0.65)
                        : Color.black.opacity(0.12),
                    lineWidth: isFocusedPane && isSplitMode ? 1.5 : 0.8
                )
        )
    }
}

struct ViewportSwipeEdgeIndicatorView: View {
    let accentColor: Color
    @ObservedObject var gestures = TrackpadGestureManager.shared

    var body: some View {
        HStack {
            if gestures.viewportSwipeProgress > 0.05 {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 36, height: 36)
                        .shadow(radius: 6)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .offset(x: min(gestures.viewportSwipeProgress * 48, 48))
                .transition(.opacity)
            }
            Spacer()
            if gestures.viewportSwipeProgress < -0.05 {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 36, height: 36)
                        .shadow(radius: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .offset(x: max(gestures.viewportSwipeProgress * 48, -48))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct ViewportZapperBannerView: View {
    let tabID: UUID

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "scissors")
                .foregroundStyle(.white)
            Text("Click any element on the page to hide it")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button("Done") {
                WebViewPool.shared.setElementZapperActive(false, for: tabID)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.92))
        .clipShape(Capsule())
        .shadow(radius: 8)
        .padding(.top, 12)
        .padding(.horizontal, 24)
    }
}
