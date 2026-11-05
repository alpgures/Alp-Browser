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
                WebViewRepresentable(
                    tab: tab,
                    isFocusedPane: isFocusedPane,
                    onFocus: {
                        if browserState.activeTabID != tab.id {
                            browserState.activeTabID = tab.id
                        }
                    }
                )
            case .canvas(let canvasID):
                CanvasBoardView(canvasID: canvasID)
            case .note(let noteID):
                NoteEditorView(noteID: noteID)
            }

            // Top Loading Progress Bar
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

            // Trackpad Back / Forward Navigation Edge Indicator
            if isFocusedPane {
                ViewportSwipeEdgeIndicatorView(accentColor: browserState.activeTheme.primaryColor.swiftUIColor)
            }

            // Active Element Zapper Banner
            if isFocusedPane && WebViewPool.shared.isZapperModeActive {
                ViewportZapperBannerView(tabID: tab.id)
            }

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
                        browserState.removeSplitPane()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Close Split View")
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
            Image(systemName: "bolt.fill")
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
