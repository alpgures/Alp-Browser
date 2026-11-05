//
//  TrackpadGestureManager.swift
//  Alp Browser
//
//  Smooth macOS trackpad multi-touch gesture monitor.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
public final class TrackpadGestureManager: ObservableObject {
    public static let shared = TrackpadGestureManager()

    /// Continuous horizontal finger offset (in points) while swiping on the Sidebar
    @Published public var sidebarSwipeOffset: CGFloat = 0

    /// Whether the user is actively swiping across the sidebar space pager
    @Published public var isDraggingSidebarPager: Bool = false

    /// Interactive progress for navigation on the Web Viewport (-1.0 = forward, +1.0 = back)
    @Published public var viewportSwipeProgress: CGFloat = 0

    /// Direction of the slide transition when switching spaces (-1 or +1)
    @Published public var spaceTransitionDirection: Int = 1

    private var localEventMonitor: Any?
    private var flagsEventMonitor: Any?

    private enum GestureTarget {
        case none
        case sidebar
        case viewport
        case peek
    }

    private var activeTarget: GestureTarget = .none
    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private var hasLockedAxis: Bool = false
    private var isHorizontalGesture: Bool = false
    private var hasCommittedInCurrentGesture: Bool = false

    private init() {}

    public func startMonitoring() {
        guard localEventMonitor == nil else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .swipe, .magnify, .smartMagnify, .keyDown]
        ) { [weak self] event in
            guard let self = self else { return event }
            return self.handleEvent(event)
        }

        flagsEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            self.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let state = BrowserState.shared
        if state.isTabSwitcherPresented && !event.modifierFlags.contains(.control) {
            state.commitTabSwitcherSelection()
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            // Control + Tab / Control + Shift + Tab (keyCode 48 is Tab)
            if event.keyCode == 48 && event.modifierFlags.contains(.control) {
                let backwards = event.modifierFlags.contains(.shift)
                BrowserState.shared.stepTabSwitcher(backwards: backwards)
                return nil
            }
            // Escape key closes overlays
            if event.keyCode == 53 {
                let state = BrowserState.shared
                if state.isTabSwitcherPresented {
                    state.isTabSwitcherPresented = false
                    return nil
                }
                if state.peekSession != nil {
                    state.peekSession = nil
                    return nil
                }
                if state.isSiteControlCenterPresented {
                    state.isSiteControlCenterPresented = false
                    return nil
                }
            }
            return event

        case .swipe:
            let state = BrowserState.shared
            if isLocationInSidebar(event) {
                if event.deltaX < 0 {
                    spaceTransitionDirection = 1
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        state.switchToNextSpace(forward: true)
                    }
                    performHaptic()
                } else if event.deltaX > 0 {
                    spaceTransitionDirection = -1
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        state.switchToNextSpace(forward: false)
                    }
                    performHaptic()
                }
                return nil
            } else {
                if event.deltaX > 0 {
                    state.goBackInActiveTab()
                    performHaptic()
                } else if event.deltaX < 0 {
                    state.goForwardInActiveTab()
                    performHaptic()
                }
                return nil
            }

        case .magnify:
            let state = BrowserState.shared
            if state.peekSession != nil && event.magnification > 0.28 {
                performHaptic()
                state.expandPeekToFullTab()
                return nil
            } else if state.peekSession != nil && event.magnification < -0.28 {
                performHaptic()
                state.peekSession = nil
                return nil
            }
            if let activeID = state.activeTabID,
               let wv = WebViewPool.shared.existingWebView(for: activeID) {
                let newZoom = min(max(wv.pageZoom + event.magnification * 0.65, 0.5), 3.0)
                wv.pageZoom = newZoom
            }
            return event

        case .smartMagnify:
            if let activeID = BrowserState.shared.activeTabID,
               let wv = WebViewPool.shared.existingWebView(for: activeID) {
                wv.pageZoom = (abs(wv.pageZoom - 1.0) > 0.05) ? 1.0 : 1.30
                performHaptic()
            }
            return event

        case .scrollWheel:
            return handleScrollWheel(event)

        default:
            return event
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas else { return event }

        let phase = event.phase

        if phase == .began {
            resetGestureTracking()
            if BrowserState.shared.peekSession != nil {
                activeTarget = .peek
            } else if isLocationInSidebar(event) {
                activeTarget = .sidebar
            } else {
                activeTarget = .viewport
            }
        }

        if event.momentumPhase != [] {
            return isHorizontalGesture && activeTarget == .sidebar ? nil : event
        }

        if phase == .changed || phase == .began {
            guard !hasCommittedInCurrentGesture else {
                return activeTarget == .sidebar ? nil : event
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            accumulatedDeltaX += dx
            accumulatedDeltaY += dy

            if !hasLockedAxis {
                let totalMovement = hypot(accumulatedDeltaX, accumulatedDeltaY)
                if totalMovement > 6.0 {
                    hasLockedAxis = true
                    isHorizontalGesture = abs(accumulatedDeltaX) > abs(accumulatedDeltaY) * 1.2
                    if isHorizontalGesture && activeTarget == .sidebar {
                        isDraggingSidebarPager = true
                    }
                }
            }

            guard hasLockedAxis && isHorizontalGesture else {
                return event
            }

            switch activeTarget {
            case .sidebar:
                handleSidebarHorizontalSwipe()
                return nil

            case .viewport:
                handleViewportHorizontalSwipe()
                return event

            case .peek:
                return nil

            case .none:
                return event
            }
        }

        if phase == .ended || phase == .cancelled {
            let wasSidebarHorizontal = (activeTarget == .sidebar && isHorizontalGesture)
            finishGesture()
            return wasSidebarHorizontal ? nil : event
        }

        return event
    }

    private func handleSidebarHorizontalSwipe() {
        let state = BrowserState.shared
        let spaceCount = state.spaces.count
        guard spaceCount > 0 else { return }
        let currentIdx = state.activeSpaceIndex ?? 0
        let threshold: CGFloat = 65.0

        if state.isLibrarySheetPresented {
            // Library drawer is already revealed: swiping left slides it closed
            if accumulatedDeltaX < -threshold {
                hasCommittedInCurrentGesture = true
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    state.isLibrarySheetPresented = false
                }
                performHaptic()
            }
            return
        }

        if accumulatedDeltaX > 0 {
            // Swiping Right
            if currentIdx == 0 {
                // On leftmost space: swiping right reveals the Library from the side!
                sidebarSwipeOffset = min(accumulatedDeltaX * 0.35, 45.0)
                if accumulatedDeltaX > threshold {
                    hasCommittedInCurrentGesture = true
                    sidebarSwipeOffset = 0
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        state.isLibrarySheetPresented = true
                    }
                    performHaptic()
                }
            } else {
                // On intermediate space: swiping right switches to previous space (leftwards)
                sidebarSwipeOffset = min(accumulatedDeltaX * 0.35, 45.0)
                if accumulatedDeltaX > threshold {
                    hasCommittedInCurrentGesture = true
                    sidebarSwipeOffset = 0
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        state.switchToSpace(at: currentIdx - 1)
                    }
                    performHaptic()
                }
            }
        } else if accumulatedDeltaX < 0 {
            // Swiping Left
            let isRightmost = (currentIdx >= spaceCount - 1)
            if isRightmost {
                // On rightmost space: DO NOTHING except elastic rubber-band rebound animation!
                sidebarSwipeOffset = max(accumulatedDeltaX * 0.22, -35.0)
                // When gesture ends, finishGesture() springs sidebarSwipeOffset back to 0!
            } else {
                // On intermediate space: swiping left switches to next space (rightwards)
                sidebarSwipeOffset = max(accumulatedDeltaX * 0.35, -45.0)
                if accumulatedDeltaX < -threshold {
                    hasCommittedInCurrentGesture = true
                    sidebarSwipeOffset = 0
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        state.switchToSpace(at: currentIdx + 1)
                    }
                    performHaptic()
                }
            }
        }
    }

    private func handleViewportHorizontalSwipe() {
        let state = BrowserState.shared
        let progress = min(max(accumulatedDeltaX / 120.0, -1.0), 1.0)
        viewportSwipeProgress = progress

        if accumulatedDeltaX > 90.0 && state.canGoBackInActiveTab {
            hasCommittedInCurrentGesture = true
            state.goBackInActiveTab()
            performHaptic()
        } else if accumulatedDeltaX < -90.0 && state.canGoForwardInActiveTab {
            hasCommittedInCurrentGesture = true
            state.goForwardInActiveTab()
            performHaptic()
        }
    }

    private func finishGesture() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            sidebarSwipeOffset = 0
            viewportSwipeProgress = 0
            isDraggingSidebarPager = false
        }
        resetGestureTracking()
    }

    private func resetGestureTracking() {
        activeTarget = .none
        accumulatedDeltaX = 0
        accumulatedDeltaY = 0
        hasLockedAxis = false
        isHorizontalGesture = false
        hasCommittedInCurrentGesture = false
    }

    private func isLocationInSidebar(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        let location = event.locationInWindow
        let sidebarWidth = BrowserState.shared.isSidebarCollapsed ? 0 : BrowserState.shared.sidebarWidth
        return location.x <= sidebarWidth && location.y >= 0 && location.y <= window.frame.height
    }

    private func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
}
