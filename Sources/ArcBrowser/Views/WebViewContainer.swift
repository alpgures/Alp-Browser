import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

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

// MARK: - Single or Split Pane Content Host (Zero Re-Render Storms During Gestures)

public struct ViewportPaneView: View {
    @EnvironmentObject var browserState: BrowserState

    public let tab: TabItem
    public let isSplitMode: Bool
    public let isFocusedPane: Bool

    @State private var isHoveringHeader = false
    @State private var isTargetedForSplitDrop = false

    public var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)

            switch tab.kind {
            case .web:
                WebViewRepresentable(
                    tab: tab,
                    isFocusedPane: isFocusedPane,
                    onFocus: {
                        if browserState.activeTabID != tab.id {
                            browserState.activeTabID = tab.id
                        }
                    }
                )
            case .easel(let easelID):
                EaselCanvasView(easelID: easelID)
            case .note(let noteID):
                NoteEditorView(noteID: noteID)
            }

            // 1. Loading Progress Bar at Top of Viewport
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
            }

            // 2. Isolated 120Hz Interactive Two-Finger Trackpad Back / Forward Edge Swipe Indicator
            if isFocusedPane {
                ViewportSwipeEdgeIndicatorView(primaryColor: browserState.activeTheme.primaryColor.swiftUIColor)
            }

            // 3. Isolated Element Zapper Banner
            if isFocusedPane {
                ViewportZapperBannerView(tabID: tab.id)
            }

            // 4. Split View Mini Header Pill (shown at top of each split pane)
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
                        browserState.toggleSplitOrientation()
                    } label: {
                        Image(systemName: browserState.activeSpace.splitOrientation == .horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Split Orientation")

                    Button {
                        browserState.removeSplitPane(tabID: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Close Split Pane (⌃⇧-)")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: 260)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                .padding(.top, 6)
                .opacity(isHoveringHeader || isFocusedPane ? 0.95 : 0.35)
                .onHover { isHoveringHeader = $0 }
            }

            // 5. Isolated Arc Hover Link Status Bar Pill (Bottom-Left of Viewport)
            if isFocusedPane {
                ViewportHoverLinkStatusPillView()
            }

            // 6. Drag-Tab-to-Viewport Split View Drop Indicator
            if isTargetedForSplitDrop {
                HStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.split.2x1.fill")
                            .font(.system(size: 28))
                        Text("Drop Tab to Open in Split View")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 320, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(browserState.activeTheme.primaryColor.swiftUIColor.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.65), lineWidth: 2)
                            )
                    )
                    .padding(12)
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSplitMode && isFocusedPane
                        ? browserState.activeTheme.effectiveAccentColor.opacity(0.85)
                        : Color.black.opacity(0.12),
                    lineWidth: isSplitMode && isFocusedPane ? 2.0 : 0.5
                )
        )
        .onDrop(of: [.text], isTargeted: $isTargetedForSplitDrop) { providers in
            guard let first = providers.first else { return false }
            first.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                let rawString: String?
                if let data = item as? Data {
                    rawString = String(data: data, encoding: .utf8)
                } else {
                    rawString = item as? String
                }
                if let str = rawString, let droppedTabID = UUID(uuidString: str) {
                    Task { @MainActor in
                        BrowserState.shared.addSplitPane(withTabID: droppedTabID)
                    }
                }
            }
            return true
        }
    }
}

// MARK: - Isolated 120Hz Leaf Views (Prevents WebView & Parent View Re-Renders)

private struct ViewportSwipeEdgeIndicatorView: View {
    @ObservedObject var gestureManager = TrackpadGestureManager.shared
    let primaryColor: Color

    var body: some View {
        let progress = gestureManager.viewportSwipeProgress
        if abs(progress) > 0.03 {
            let isBack = progress > 0
            let absProgress = min(abs(progress), 1.25)
            let isReady = absProgress >= 1.0

            GeometryReader { geo in
                let offsetDistance = min(absProgress * 46.0, 58.0)
                ZStack {
                    Circle()
                        .fill(isReady ? primaryColor : Color.black.opacity(0.68))
                        .frame(width: isReady ? 46 : 38, height: isReady ? 46 : 38)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isReady ? 0.72 : 0.25), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

                    Image(systemName: isBack ? "arrow.left" : "arrow.right")
                        .font(.system(size: isReady ? 17 : 14, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(isReady ? 1.12 : 0.92)
                }
                .position(
                    x: isBack ? (-18 + offsetDistance) : (geo.size.width + 18 - offsetDistance),
                    y: geo.size.height / 2.0
                )
                .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.78), value: isReady)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct ViewportZapperBannerView: View {
    @ObservedObject var webViewPool = WebViewPool.shared
    let tabID: UUID

    var body: some View {
        if webViewPool.isZapperModeActive {
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(.purple)
                Text("Arc Boost Zapper: Click any element on the page to hide it permanently")
                    .font(.system(size: 12, weight: .semibold))
                Button("Done") {
                    webViewPool.setElementZapperActive(false, for: tabID)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.purple.opacity(0.5), lineWidth: 1))
            .padding(.top, 12)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
    }
}

private struct ViewportHoverLinkStatusPillView: View {
    @ObservedObject var webViewPool = WebViewPool.shared

    var body: some View {
        if let hoveredURL = webViewPool.hoveredLinkURL, !hoveredURL.isEmpty {
            VStack {
                Spacer()
                HStack {
                    Text(hoveredURL)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.6)
                        )
                        .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
                        .padding(.leading, 10)
                        .padding(.bottom, 10)
                    Spacer()
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
