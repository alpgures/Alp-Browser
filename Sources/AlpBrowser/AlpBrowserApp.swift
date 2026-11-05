//
//  AlpBrowserApp.swift
//  Alp Browser
//
//  Application lifecycle, menus, and standalone Mini Alp window controller.
//  Copyright © 2026 Alp Gures. All rights reserved.
//

import SwiftUI
import AppKit

@main
public struct AlpBrowserApp: App {
    @NSApplicationDelegateAdaptor(AlpAppDelegate.self) var appDelegate
    @StateObject private var browserState = BrowserState.shared

    public init() {}

    public var body: some Scene {
        WindowGroup("Alp Browser") {
            MainBrowserWindow()
                .environmentObject(browserState)
                .frame(minWidth: 780, minHeight: 520)
                .ignoresSafeArea()
                .background(AlpWindowAccessor())
                .onOpenURL { url in
                    browserState.handleCommandBarInput(url.absoluteString, openInNewTab: false)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    browserState.isSettingsPresented = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(replacing: .newItem) {
                Button("New Tab Page") {
                    browserState.openStartTab()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Button("Command Bar / New Tab") {
                    browserState.openCommandBar(prefilledWithCurrentURL: false)
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Focus URL in Command Bar") {
                    browserState.openCommandBar(prefilledWithCurrentURL: true)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("New Mini Alp Window") {
                    MiniAlpWindowController.shared.showWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button("New Canvas") {
                    browserState.createNewCanvas(title: "New Canvas")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("New Note") {
                    browserState.createNewNote(title: "Quick Note")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Close Tab") {
                    if browserState.isCommandBarPresented {
                        browserState.isCommandBarPresented = false
                    } else if browserState.peekSession != nil {
                        browserState.peekSession = nil
                    } else if let id = browserState.activeTabID {
                        browserState.closeTab(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        browserState.isSidebarCollapsed.toggle()
                        browserState.isSidebarHoverPeeking = false
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Copy Current URL") {
                    if let url = browserState.activeTab?.urlString {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        browserState.showToast("Copied URL to clipboard")
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Pin / Unpin Current Tab") {
                    if let id = browserState.activeTabID {
                        browserState.togglePinTab(id: id)
                    }
                }
                .keyboardShortcut("d", modifiers: [.command])

                Divider()

                Button("Add Split View Pane") {
                    browserState.addSplitPane()
                }
                .keyboardShortcut("=", modifiers: [.control, .shift])

                Button("Close Split View Pane") {
                    browserState.removeSplitPane()
                }
                .keyboardShortcut("-", modifiers: [.control, .shift])

                Button("Exit Split View") {
                    browserState.closeSplitView()
                }
                .disabled(!browserState.isSplitActive)

                Button("Switch Split View Direction") {
                    browserState.toggleSplitOrientation()
                }
                .keyboardShortcut("\\", modifiers: [.control, .shift])
                .disabled(!browserState.isSplitActive)

                Button("Grow Focused Split Pane") {
                    browserState.resizeFocusedSplitPane(grow: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.control, .option])
                .disabled(!browserState.isSplitActive)

                Button("Shrink Focused Split Pane") {
                    browserState.resizeFocusedSplitPane(grow: false)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.control, .option])
                .disabled(!browserState.isSplitActive)

                Button("Grow Focused Split Pane (Up)") {
                    browserState.resizeFocusedSplitPane(grow: true)
                }
                .keyboardShortcut(.upArrow, modifiers: [.control, .option])
                .disabled(!browserState.isSplitActive)

                Button("Shrink Focused Split Pane (Down)") {
                    browserState.resizeFocusedSplitPane(grow: false)
                }
                .keyboardShortcut(.downArrow, modifiers: [.control, .option])
                .disabled(!browserState.isSplitActive)

                Button("Move Focused Split Pane Forward") {
                    browserState.moveFocusedSplitPane(forward: true)
                }
                .keyboardShortcut("]", modifiers: [.control, .command])
                .disabled(!browserState.isSplitActive)

                Button("Move Focused Split Pane Backward") {
                    browserState.moveFocusedSplitPane(forward: false)
                }
                .keyboardShortcut("[", modifiers: [.control, .command])
                .disabled(!browserState.isSplitActive)

                Button("Focus Next Split Pane") {
                    browserState.focusSplitPane(forward: true)
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(!browserState.isSplitActive)

                Button("Focus Previous Split Pane") {
                    browserState.focusSplitPane(forward: false)
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(!browserState.isSplitActive)

                Divider()

                Button("Find in Page") {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        browserState.isFindBarPresented.toggle()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Customize Page Style") {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        browserState.isStyleStudioPresented.toggle()
                    }
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Reload Page") {
                    if let id = browserState.activeTabID {
                        WebViewPool.shared.reload(in: id)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Navigate Back") {
                    browserState.goBackInActiveTab()
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("Navigate Forward") {
                    browserState.goForwardInActiveTab()
                }
                .keyboardShortcut("]", modifiers: [.command])

                Button("Capture Page to Canvas") {
                    Task {
                        await browserState.capturePageToCanvasOrClipboard(sendToCanvas: true)
                    }
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])

                Divider()

                Button("Hibernate Background Tabs (0 MB RAM)") {
                    Task {
                        await browserState.hibernateAllBackgroundTabsNow()
                    }
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Sync Vault Now") {
                    Task {
                        await browserState.syncNow()
                    }
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])

                Button("Import Spaces from Arc") {
                    browserState.importFromInstalledArcBrowser()
                }
            }

            CommandMenu("Spaces") {
                Button("Next Space") {
                    browserState.switchToNextSpace(forward: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                Button("Previous Space") {
                    browserState.switchToNextSpace(forward: false)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Divider()

                ForEach(0..<min(browserState.spaces.count, 9), id: \.self) { index in
                    let space = browserState.spaces[index]
                    Button("\(space.iconEmoji) \(space.title)") {
                        browserState.switchToSpace(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.control])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(browserState)
        }
    }
}

// MARK: - AppKit Window Configurator & AppDelegate

@MainActor
public final class AlpAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Set clean app icon on startup immediately
        let iconName = UserDefaults.standard.string(forKey: "alp_selected_icon") ?? "alp_browser_original"
        if iconName == "custom" {
            if let customImg = AlpIconGenerator.loadCustomIconFromDisk()
                ?? AlpIconGenerator.generateCustomIcon(config: BrowserState.shared.customIconConfig) {
                NSApp.applicationIconImage = customImg
            }
        } else {
            if let img = AlpIconGenerator.bundledIcon(named: iconName) {
                NSApp.applicationIconImage = img
            }
        }

        NSApp.activate(ignoringOtherApps: true)

        // Ensure "Settings..." is explicitly wired in the macOS Alp Browser menu
        setupApplicationMenu()
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setupApplicationMenu()
            }
        }
    }

    /// Links opened from other apps (when Alp is the default browser) land in the compact
    /// Mini Alp window; alp:// links are routed to the main window as before.
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let scheme = url.scheme?.lowercased() else { continue }
            if scheme == "http" || scheme == "https" {
                MiniAlpWindowController.shared.showWindow(initialURL: url.absoluteString)
            }
        }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        ensureSettingsItem(in: menu)
    }

    private func setupApplicationMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let appMenuItem = mainMenu.items.first, let appMenu = appMenuItem.submenu else { return }
        appMenu.delegate = self
        ensureSettingsItem(in: appMenu)
    }

    private func ensureSettingsItem(in appMenu: NSMenu) {
        let hasSettings = appMenu.items.contains { item in
            item.action == #selector(openSettingsAction) || (item.keyEquivalent == "," && item.keyEquivalentModifierMask == .command)
        }
        if !hasSettings {
            let settingsItem = NSMenuItem(
                title: "Settings...",
                action: #selector(openSettingsAction),
                keyEquivalent: ","
            )
            settingsItem.target = self
            if appMenu.items.count > 1 {
                appMenu.insertItem(settingsItem, at: 1)
                appMenu.insertItem(NSMenuItem.separator(), at: 2)
            } else {
                appMenu.addItem(settingsItem)
            }
        }
    }

    @objc private func openSettingsAction() {
        BrowserState.shared.isSettingsPresented = true
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        BrowserState.shared.saveImmediately()
    }
}

/// Keeps the system traffic lights on the same horizontal centre line as the top-bar icons and URL pill.
enum AlpWindowChrome {
    static func alignTrafficLights(in window: NSWindow) {
        guard window.styleMask.contains(.titled), !window.styleMask.contains(.fullScreen) else { return }
        let targetY = window.frame.height - AlpTopBarMetrics.centerY   // window coordinates, origin bottom-left
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type), let container = button.superview else { continue }
            let currentY = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil).y
            let delta = targetY - currentY
            guard abs(delta) > 0.5 else { continue }
            let dy = container.isFlipped ? -delta : delta
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: button.frame.origin.y + dy))
        }
    }
}

private final class AlpWindowAccessorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window = self.window {
            configure(window: window)
            // AppKit re-lays the buttons out on resize, key changes and full-screen exits; re-apply after it does.
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.didExitFullScreenNotification
            ]
            for name in names {
                NotificationCenter.default.addObserver(self, selector: #selector(realignTrafficLights), name: name, object: window)
            }
        }
    }

    @objc private func realignTrafficLights() {
        guard let window = self.window else { return }
        AlpWindowChrome.alignTrafficLights(in: window)
        // Some of those notifications fire before AppKit finishes its own layout pass.
        DispatchQueue.main.async { [weak window] in
            if let window { AlpWindowChrome.alignTrafficLights(in: window) }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configure(window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.toolbar = nil
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        if window.frame.width < 1100 {
            window.setContentSize(NSSize(width: 1320, height: 840))
            window.center()
        }
        AlpWindowChrome.alignTrafficLights(in: window)
        DispatchQueue.main.async { [weak window] in
            if let window { AlpWindowChrome.alignTrafficLights(in: window) }
        }
    }
}

struct AlpWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = AlpWindowAccessorView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isOpaque = false
                window.backgroundColor = .clear
                window.toolbar = nil
                window.titlebarSeparatorStyle = .none
                window.isMovableByWindowBackground = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Mini Alp Standalone Window (⌘⌥N)

@MainActor
public final class MiniAlpWindowController {
    public static let shared = MiniAlpWindowController()
    private var window: NSWindow?

    public func showWindow(initialURL: String = "https://www.google.com") {
        window?.close()
        let contentView = MiniAlpView(initialURL: initialURL) { [weak self] in
            self?.window?.close()
        }
        .environmentObject(BrowserState.shared)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: contentView)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.window = panel
    }
}

struct MiniAlpView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var urlInput: String
    @State private var miniTab: TabItem
    let onClose: () -> Void

    init(initialURL: String, onClose: @escaping () -> Void) {
        _urlInput = State(initialValue: initialURL)
        _miniTab = State(initialValue: TabItem(title: "Mini Alp", urlString: initialURL))
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer().frame(width: 56)

                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(browserState.activeTheme.accentColor.swiftUIColor)

                TextField("Mini Alp Quick Lookup...", text: $urlInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .onSubmit {
                        let resolved = browserState.resolveInputToURLString(urlInput)
                        miniTab.urlString = resolved
                        WebViewPool.shared.loadURL(resolved, in: miniTab.id)
                    }

                Menu {
                    ForEach(Array(browserState.spaces.enumerated()), id: \.element.id) { idx, sp in
                        Button("Open in \(sp.iconEmoji) \(sp.title)") {
                            browserState.switchToSpace(at: idx)
                            browserState.openNewTab(urlString: miniTab.urlString, title: miniTab.title)
                            WebViewPool.shared.destroyWebView(for: miniTab.id)
                            onClose()
                        }
                    }
                } label: {
                    Label("Expand to Space", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        browserState.activeTheme.primaryColor.swiftUIColor,
                        browserState.activeTheme.secondaryColor.swiftUIColor
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            WebViewRepresentable(tab: miniTab)
        }
        .onDisappear {
            WebViewPool.shared.destroyWebView(for: miniTab.id)
        }
    }
}
