import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
public final class TrackpadGestureManager: ObservableObject {
    public static let shared = TrackpadGestureManager()

    /// Continuous 1:1 horizontal finger offset (in points) while swiping on the Sidebar to switch Spaces
    @Published public var sidebarSwipeOffset: CGFloat = 0

    /// Whether the user's fingers are actively dragging the sidebar space pager
    @Published public var isDraggingSidebarPager: Bool = false

    /// Interactive progress (-1.0 = Forward swipe from right, +1.0 = Back swipe from left) on the Web Viewport
    @Published public var viewportSwipeProgress: CGFloat = 0

    /// Direction of the slide transition when switching Spaces (-1 or +1)
    @Published public var spaceTransitionDirection: Int = 1

    private var localEventMonitor: Any?
    private var flagsEventMonitor: Any?

    // Gesture tracking state
    private enum GestureTarget {
        case none
        case sidebar
        case viewport
        case peek
    }

    private var activeTarget: GestureTarget = .none
    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private var lastScrollingDeltaX: CGFloat = 0
    private var hasLockedAxis: Bool = false
    private var isHorizontalGesture: Bool = false
    private var hasTriggeredThresholdHaptic: Bool = false
    private var hasCommittedInCurrentGesture: Bool = false

    private init() {}

    public func startMonitoring() {
        guard localEventMonitor == nil else { return }

        // Initialize ArcAssetLoader on startup so fonts and bundles from Arc.app are registered immediately
        _ = ArcAssetLoader.shared

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
        // When user releases the Control key while the Control+Tab switcher is visible, commit selection
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
                BrowserState.shared.StepTabSwitcher(backwards: backwards)
                return nil
            }
            // Escape closes overlays
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
            // Three-finger trackpad swipe fallback
            let state = BrowserState.shared
            if isLocationInSidebar(event) {
                if event.deltaX < 0 {
                    spaceTransitionDirection = 1
                    withAnimation(.interpolatingSpring(mass: 1.0, stiffness: 320, damping: 32)) {
                        state.switchToNextSpace(forward: true)
                    }
                    performHaptic(.alignment)
                } else if event.deltaX > 0 {
                    spaceTransitionDirection = -1
                    withAnimation(.interpolatingSpring(mass: 1.0, stiffness: 320, damping: 32)) {
                        state.switchToNextSpace(forward: false)
                    }
                    performHaptic(.alignment)
                }
                return nil
            } else {
                if event.deltaX > 0 {
                    state.goBackInActiveTab()
                    performHaptic(.generic)
                } else if event.deltaX < 0 {
                    state.goForwardInActiveTab()
                    performHaptic(.generic)
                }
                return nil
            }

        case .magnify:
            // Pinch-to-zoom on Trackpad
            let state = BrowserState.shared
            if state.peekSession != nil && event.magnification > 0.28 {
                performHaptic(.levelChange)
                state.expandPeekToFullTab()
                return nil
            } else if state.peekSession != nil && event.magnification < -0.28 {
                performHaptic(.alignment)
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
            // Two-finger double-tap resets page zoom to 100%
            if let activeID = BrowserState.shared.activeTabID,
               let wv = WebViewPool.shared.existingWebView(for: activeID) {
                wv.pageZoom = (abs(wv.pageZoom - 1.0) > 0.05) ? 1.0 : 1.35
                performHaptic(.alignment)
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

        // 1. Handle finger touch-down (.began)
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

        // 2. Ignore post-lift momentum events once the finger gesture has finished
        if event.momentumPhase != [] {
            return isHorizontalGesture && activeTarget == .sidebar ? nil : event
        }

        // 3. Handle active finger movement (.began / .changed)
        if phase == .changed || phase == .began {
            guard !hasCommittedInCurrentGesture else {
                return activeTarget == .sidebar ? nil : event
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            lastScrollingDeltaX = dx
            accumulatedDeltaX += dx
            accumulatedDeltaY += dy

            if !hasLockedAxis {
                let totalMovement = hypot(accumulatedDeltaX, accumulatedDeltaY)
                if totalMovement > 5.0 {
                    hasLockedAxis = true
                    isHorizontalGesture = abs(accumulatedDeltaX) > abs(accumulatedDeltaY) * 1.15
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
                // Consume horizontal scroll events on the sidebar so vertical scrollviews don't jitter
                return nil

            case .viewport:
                handleViewportHorizontalSwipe()
                return event

            case .peek:
                handlePeekHorizontalSwipe()
                return nil

            case .none:
                return event
            }
        }

        // 4. Handle finger lift (.ended / .cancelled)
        if phase == .ended || phase == .cancelled {
            let wasSidebarHorizontal = (activeTarget == .sidebar && isHorizontalGesture)
            finishGesture()
            return wasSidebarHorizontal ? nil : event
        }

        return event
    }

    // MARK: - 120Hz 1:1 Interactive Sidebar Space Pager (`SidebarPagingContainerScrollView` behavior)

    private func handleSidebarHorizontalSwipe() {
        let state = BrowserState.shared
        let spaceCount = state.spaces.count
        guard spaceCount > 1 else { return }

        let currentIndex = state.activeSpaceIndex ?? 0
        let pageWidth = max(state.sidebarWidth, 200)

        // Apply authentic rubber-banding at the first and last Space edges,
        // and 1:1 finger tracking between existing Spaces.
        let effectiveOffset: CGFloat
        if (currentIndex == 0 && accumulatedDeltaX > 0) ||
           (currentIndex == spaceCount - 1 && accumulatedDeltaX < 0) {
            effectiveOffset = accumulatedDeltaX * 0.26
        } else {
            effectiveOffset = max(min(accumulatedDeltaX, pageWidth), -pageWidth)
        }

        sidebarSwipeOffset = effectiveOffset

        // Haptic tick when crossing the commit threshold (~26% of sidebar width)
        let threshold = pageWidth * 0.26
        let canAdvanceForward = currentIndex < spaceCount - 1 && accumulatedDeltaX <= -threshold
        let canAdvanceBackward = currentIndex > 0 && accumulatedDeltaX >= threshold

        if (canAdvanceForward || canAdvanceBackward) && !hasTriggeredThresholdHaptic {
            hasTriggeredThresholdHaptic = true
            performHaptic(.alignment)
        } else if abs(accumulatedDeltaX) < threshold * 0.85 && hasTriggeredThresholdHaptic {
            hasTriggeredThresholdHaptic = false
        }
    }

    private func commitSidebarSwipeIfNeeded() {
        let state = BrowserState.shared
        let spaceCount = state.spaces.count
        guard spaceCount > 1 else {
            withAnimation(.interpolatingSpring(mass: 1.0, stiffness: 340, damping: 32)) {
                sidebarSwipeOffset = 0
                isDraggingSidebarPager = false
            }
            return
        }

        let currentIndex = state.activeSpaceIndex ?? 0
        let pageWidth = max(state.sidebarWidth, 200)
        let displacementThreshold = pageWidth * 0.24
        let velocityThreshold: CGFloat = 7.0

        var targetIndex = currentIndex
        // Fingers moving left (negative deltaX) -> next space (currentIndex + 1)
        if (accumulatedDeltaX <= -displacementThreshold || lastScrollingDeltaX <= -velocityThreshold) && currentIndex < spaceCount - 1 {
            targetIndex = currentIndex + 1
            spaceTransitionDirection = 1
        }
        // Fingers moving right (positive deltaX) -> previous space (currentIndex - 1)
        else if (accumulatedDeltaX >= displacementThreshold || lastScrollingDeltaX >= velocityThreshold) && currentIndex > 0 {
            targetIndex = currentIndex - 1
            spaceTransitionDirection = -1
        }

        if targetIndex != currentIndex && !hasTriggeredThresholdHaptic {
            performHaptic(.alignment)
        }

        // Because the horizontal pager offset is `-CGFloat(activeSpaceIndex) * pageWidth + sidebarSwipeOffset`,
        // updating `switchToSpace(at: targetIndex)` and `sidebarSwipeOffset = 0` inside the same spring transaction
        // animates the remaining distance seamlessly with zero jump!
        withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 340, damping: 31)) {
            if targetIndex != currentIndex {
                state.switchToSpace(at: targetIndex)
            }
            sidebarSwipeOffset = 0
            isDraggingSidebarPager = false
        }
    }

    // MARK: - 120Hz Viewport Two-Finger Horizontal Back/Forward Swipe

    private func handleViewportHorizontalSwipe() {
        let state = BrowserState.shared
        let canBack = state.canGoBackInActiveTab
        let canForward = state.canGoForwardInActiveTab

        // Effortless 68pt pull threshold
        let triggerThreshold: CGFloat = 68

        // accumulatedDeltaX > 0: fingers moving right (pulling left edge -> Back)
        // accumulatedDeltaX < 0: fingers moving left (pulling right edge -> Forward)
        if accumulatedDeltaX > 0 && canBack {
            let progress = min(accumulatedDeltaX / triggerThreshold, 1.25)
            viewportSwipeProgress = progress
            if progress >= 1.0 && !hasTriggeredThresholdHaptic {
                hasTriggeredThresholdHaptic = true
                performHaptic(.alignment)
            } else if progress < 0.88 && hasTriggeredThresholdHaptic {
                hasTriggeredThresholdHaptic = false
            }
        } else if accumulatedDeltaX < 0 && canForward {
            let progress = max(accumulatedDeltaX / triggerThreshold, -1.25)
            viewportSwipeProgress = progress
            if progress <= -1.0 && !hasTriggeredThresholdHaptic {
                hasTriggeredThresholdHaptic = true
                performHaptic(.alignment)
            } else if progress > -0.88 && hasTriggeredThresholdHaptic {
                hasTriggeredThresholdHaptic = false
            }
        } else {
            // Subtle rubberband feedback when no history in that direction
            viewportSwipeProgress = max(min(accumulatedDeltaX / 360.0, 0.20), -0.20)
        }
    }

    private func handlePeekHorizontalSwipe() {
        if abs(accumulatedDeltaX) > 90 && !hasTriggeredThresholdHaptic {
            hasTriggeredThresholdHaptic = true
            hasCommittedInCurrentGesture = true
            performHaptic(.alignment)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                BrowserState.shared.peekSession = nil
            }
        }
    }

    private func finishGesture() {
        let state = BrowserState.shared
        switch activeTarget {
        case .sidebar:
            if isHorizontalGesture {
                commitSidebarSwipeIfNeeded()
            }
        case .viewport:
            if viewportSwipeProgress >= 1.0 && state.canGoBackInActiveTab {
                state.goBackInActiveTab()
            } else if viewportSwipeProgress <= -1.0 && state.canGoForwardInActiveTab {
                state.goForwardInActiveTab()
            }
            withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 340, damping: 30)) {
                viewportSwipeProgress = 0
            }
        case .peek, .none:
            break
        }
        resetGestureTracking()
    }

    private func resetGestureTracking() {
        activeTarget = .none
        accumulatedDeltaX = 0
        accumulatedDeltaY = 0
        lastScrollingDeltaX = 0
        hasLockedAxis = false
        isHorizontalGesture = false
        hasTriggeredThresholdHaptic = false
        hasCommittedInCurrentGesture = false
    }

    private func isLocationInSidebar(_ event: NSEvent) -> Bool {
        let state = BrowserState.shared
        if state.isSidebarCollapsed && !state.isSidebarHoverPeeking {
            return false
        }
        let x = event.locationInWindow.x
        return x >= 0 && x <= (state.sidebarWidth + 12)
    }

    private func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
