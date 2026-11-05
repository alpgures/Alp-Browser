import SwiftUI
import AppKit

@main
public struct ArcBrowserApp: App {
    @NSApplicationDelegateAdaptor(ArcAppDelegate.self) var appDelegate
    @StateObject private var browserState = BrowserState.shared

    public init() {}

    public var body: some Scene {
        WindowGroup("Arc") {
            MainBrowserWindow()
                .environmentObject(browserState)
                .frame(minWidth: 780, minHeight: 520)
                .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Command Bar / New Tab") {
                    browserState.openCommandBar(prefilledWithCurrentURL: false)
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Focus URL in Command Bar") {
                    browserState.openCommandBar(prefilledWithCurrentURL: true)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("New Little Arc Window") {
                    LittleArcWindowController.shared.showWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button("New Arc Easel") {
                    browserState.createNewEasel(title: "New Easel")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("New Arc Note") {
                    browserState.createNewNote(title: "Quick Note")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Close / Unload Tab") {
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

            CommandMenu("Arc") {
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
                        browserState.showToast("Copied link to clipboard")
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

                Divider()

                Button("Find & Ask Arc Max on Page") {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        browserState.isFindAndAskBarPresented.toggle()
                    }
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Customize Site Boost") {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        browserState.isBoostStudioPresented.toggle()
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

                Button("Capture Page to Easel & Clipboard") {
                    Task {
                        await browserState.capturePageToEaselOrClipboard(sendToEasel: true)
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

                Button("Sync to OCI Cloud Box Now") {
                    Task {
                        await browserState.syncToOCICloudNow()
                    }
                }

                Button("Import from Installed Arc.app") {
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
    }
}

// MARK: - AppKit Window Configurator & AppDelegate

@MainActor
public final class ArcAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        BrowserState.shared.saveImmediately()
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.toolbar = nil
            if window.frame.width < 1100 {
                window.setContentSize(NSSize(width: 1320, height: 840))
                window.center()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Little Arc Standalone Mini Window (⌘⌥N)

@MainActor
public final class LittleArcWindowController {
    public static let shared = LittleArcWindowController()
    private var window: NSWindow?

    public func showWindow(initialURL: String = "https://www.google.com") {
        let contentView = LittleArcView(initialURL: initialURL) { [weak self] in
            self?.window?.close()
        }
        .environmentObject(BrowserState.shared)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
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

struct LittleArcView: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var urlInput: String
    @State private var miniTab: TabItem
    let onClose: () -> Void

    init(initialURL: String, onClose: @escaping () -> Void) {
        _urlInput = State(initialValue: initialURL)
        _miniTab = State(initialValue: TabItem(title: "Little Arc", urlString: initialURL))
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer().frame(width: 56)

                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(browserState.activeTheme.accentColor.swiftUIColor)

                TextField("Little Arc Quick Lookup...", text: $urlInput)
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
