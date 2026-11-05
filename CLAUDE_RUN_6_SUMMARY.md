# Claude Run 6 Summary

**Nothing was built, compiled or run.** Linux box, no Swift toolchain; the Mac build is toolchain-blocked (manifest link
failure, not a code error). Every Swift change below, including the new tests, is unbuilt and untested. Nothing was
committed or pushed. `AlpOCIBridge.m`, `ALP_REBRANDING_MANIFEST.md`, `/home/ubuntu/arc-reference` and the OCI daemon were
not touched. I did not study the Arc binary and did not open `Alp Browser.app`.

## What I changed

### 1. Zip-slip hardening
- `Services/ZipArchiveScanner.swift` (new): parses the zip central directory in memory (no external tool) and refuses the
  archive before anything is extracted. Refused: absolute paths (`/`, `\`), drive-letter paths, **any** `..` component
  (either slash style; stricter than "escapes the destination"), NUL bytes, empty names, symlinks and other special files
  (Unix mode in the external attributes), encrypted entries, Zip64 and multi-part archives (fail closed), more than 20,000
  entries, more than 512 MB declared uncompressed. It also checks that each local header name equals the central-directory
  name, so an extractor cannot see a different path than the scan did. `verifyExtractedTree` runs after extraction: no
  symlinks, no special files, nothing resolving outside the destination.
- `Services/AlpExtensionManager.swift`: `unzipPayload` now runs `ZipArchiveScanner.scan` before `ditto`, then
  `verifyExtractedTree`, then checks that the work folder holds only `payload.zip` and `unpacked`. Order is now: CRX
  signature verify (unchanged), scan, unzip, post-check.
- `Tests/AlpBrowserTests/ZipArchiveScannerTests.swift` (new): builds stored zips in memory; covers good layouts, `..`, absolute,
  backslash, drive letter, NUL, empty, symlink/FIFO, encrypted, local/central name mismatch, truncated/garbage, and the
  extracted-tree symlink check.

### 2. Note editor shortcuts (`Views/EaselNoteAndLibraryView.swift`)
- New `NoteNSTextView` (NSTextView subclass) overrides `performKeyEquivalent`: **⌘B** bold, **⌘I** italic, **⌘E** code.
  I did not use ⌘` because macOS reserves it for window cycling. They call the same `NoteTextController.wrapSelection` as the toolbar buttons, so a
  selection is wrapped and with none the placeholder is inserted and selected. They only fire while the editor is first
  responder. Edits still go through `shouldChangeText`/`didChangeText`, so undo and the 350 ms debounce are untouched.
- `NoteTextView.makeNSView` now builds the scroll view and `NoteNSTextView` by hand instead of `scrollableTextView()`
  (the same settings that function applies).

### 3. Split View
- `Services/BrowserState.swift`
  - `addSplitPane`: cap of 4 panes (toast beyond that), adding a tab that is already a pane just focuses it, the new pane's
    tab is marked active (so it is not left flagged hibernated), index re-read after `openNewTab`.
  - `removeSplitPane(tabID:)`: removes one pane (tab stays open); with fewer than two panes left the split ends and the
    remaining pane becomes the active tab. New `closeSplitView()`, `toggleSplitOrientation()`, `focusSplitPane(forward:)`, `isSplitActive`.
  - `pruneSplit`: stale or single-entry pane lists are cleared. Called on close (pinned and unpinned), permanent delete, auto-archive,
    trailing-button hibernate and store load. Before, a closed pinned tab or a deleted/archived tab stayed in the pane list.
  - Auto-archive no longer archives a tab that is showing in a split.
  - `splitRatio` is now persisted (`PersistedBrowserStore.splitRatio`, decoded with a default and clamped to 0.2–0.8, so old stores load).
    Pane list and orientation were already persisted per space.
- `Views/MainBrowserWindow.swift`: `SplitDividerView` reworked. It takes a ratio binding and applies the drag as
  start ratio + total translation / extent. The old version accumulated per-event deltas against a `leftWidth` captured
  at render time, which can drop movement when events coalesce. Cursor push/pop is now balanced (the old code could push
  twice on exit during a drag and leave the resize cursor stuck). Double-click resets to 50/50.
- `Views/WebViewContainer.swift`: `onFocusRequest` was never called anywhere, so **clicking a split pane never focused it**.
  `ClickTrackingContainerView` now watches mouse-downs with a local event monitor (passes the event through) and sets the
  pane active. The pane's ✕ now removes that pane instead of closing the whole split.
- `AlpBrowserApp.swift`: menu items Exit Split View, Switch Split View Direction (⌃⇧\), Focus Next/Previous Split Pane (⌘⌥] / ⌘⌥[).
  Existing ⌃⇧= (add) and ⌃⇧- (close focused pane) stay.
- `Views/CommandBarView.swift`: "Exit Split View" and "Switch Split View Direction" actions.
- `Models/AlpModels.swift`: `splitRatio` on the persisted store.
- `Tests/AlpBrowserTests/SplitStateTests.swift` (new): ratio default/round trip/clamp, space split state round trip.

### 4. Peek (`Views/PeekAndOverlaysView.swift`, `MainBrowserWindow`, `BrowserState`)
- **A second peek while one was open kept showing the first page**: `PeekOverlayView` kept its `@State` tab. Now
  `.id(peek.id)` rebuilds it.
- Loading state: the peek tab is not in the tab list, so loading flags never reached it. New `PeekPageState` watches the web
  view (KVO via Combine): a thin accent progress bar under the header, and the header shows the live URL.
- The peek tab id is now the session id. "Expand to Full Tab" (button and pinch gesture) and "Split View" use the page the
  peek has navigated to, not the link it opened with.
- Peek is dismissed when another tab is selected or the space changes (`selectTab`, `switchToSpace`). It used to float over a different space.
- Closing releases the KVO subscriptions, destroys the web view and drops its history stacks.
- Unchanged: trigger is Shift+click (bridge script) or Shift on a popup link; dismissal by Esc, ⌘W, scrim click, pinch-in.
  The scrim covers the sidebar, so a click there closes the peek instead of reaching the sidebar.

### 5. Tab hibernation (`Services/WebViewPool.swift`, `BrowserState.swift`)
Findings:
- **Retention path found.** `hibernateTab` took a 720 px snapshot and stored it in `snapshots` (a `@Published` dictionary);
  `captureSnapshot` also stored every screenshot-to-canvas capture there. Nothing ever displayed those images, so each
  hibernated tab kept roughly 1–2 MB of bitmap for nothing, against the "0 MB" claim. Removed: no snapshot is cached any more
  (`snapshots` is deleted; `captureSnapshot` returns the image to its caller only).
- **The "Hibernate after N minutes" setting did nothing.** `autoHibernateMinutes` was persisted and shown in Settings, but
  no timer used it; only the manual command hibernated. Added `performAutoHibernation` and a 30 s timer. It hibernates live tabs
  that have been out of sight for the chosen time; "Never" (0) disables it. Tabs on screen (including split panes) and tabs playing audio are skipped.
  It tracks "last seen on screen" itself because `lastActiveAt` is only set when a tab becomes active.
- `destroyWebView` now also removes content rule lists, calls `removeFromSuperview()` (a container still holding the view would keep it alive), and
  clears the zapper flag. It no longer loads an empty HTML string into a dying view.
- `hibernateTab` is now synchronous (it needed no await); `discardSnapshot` became `forgetTab`, which also clears the back/forward
  stacks of tabs gone for good. Stacks of hibernated tabs are kept (a few strings).
- Checked and clean: no KVO or Combine observers on tab web views, no extension-controller tab adapters, the script message handler
  is removed on destroy, the coordinator is dropped, and nothing but the pool and the hosting container references a tab's web view.
  Only `WebViewContainer` calls `webView(for:)`, and only for visible panes.
- Caveats I could not settle from code: WebKit may keep a web process alive briefly after its last view goes away (process
  cache), and an in-flight `WKDownload` may keep its originating view alive until it ends.
- Hibernated tabs reload their page on selection. Scroll position and form state are lost. There is no visual placeholder (that is why the snapshot was dead weight).

**What to measure on the Mac to confirm "0 MB"**
1. Activity Monitor (or `footprint -p <pid>`, `ps -o rss`): note the app's memory and the count of `com.apple.WebKit.WebContent` processes
   (`pgrep -f WebContent | wc -l`) with ~10 diverse tabs open (video, heavy SPA, plain page).
2. Run Tab ▸ "Hibernate Background Tabs". Within ~10–30 s, WebContent process count should fall to the number of visible panes (+ the GPU/Networking helpers), and
   the total of WebContent footprints should drop by those tabs' share. Record per-process footprint before and after.
3. The Alp Browser process itself: compare its footprint before/after. It should not rise on hibernate (the old snapshot would have added ~1–2 MB per tab). Repeat with 30 tabs; growth per hibernated tab should be ≈ 0.
4. In Instruments ▸ Leaks / Allocations (or Xcode Memory Graph) after hibernating: search for `WKWebView`, `WebViewInstanceCoordinator`, `NSImage`, `WKUserContentController`. Expect none for hibernated tab ids.
5. Auto path: set "Hibernate after 3 Minutes", leave tabs alone for ~4 min, confirm the same drop with no manual command. Confirm a tab playing audio and the visible tab stay alive.
6. Wake test: select a hibernated tab; it should reload, and memory for it returns. Hibernate again; memory should return to the baseline, not ratchet up.
7. Split: with two panes, hibernate-all must leave both panes' processes alive.
8. Sanity: `WebViewPool.liveWebViewCount` (property exists) vs. WebContent process count.

## Build risks to check first on the Mac
1. `ZipArchiveScanner.swift` (new): byte-reading helpers, `Entry`, `unicodeScalars` checks (`properties.isAlphabetic`), `FileManager.enumerator` with `for case let url as URL`.
   `ZipArchiveScannerTests.swift`: the `ZipBuilder` memberwise `Item` init with defaulted vars (trailing-default memberwise init in a private struct), `Data.dropLast` for a truncated zip.
2. `EaselNoteAndLibraryView.swift`: `NoteNSTextView` (`weak var controller` plus the `@MainActor` controller called from an `NSTextView` override) and the hand-built
   scroll view (`widthTracksTextView`, `autoresizingMask`). Runtime: text wraps to the view width, scrolls, and ⌘B/⌘I/⌘E work. Check that ⌘B/⌘I are not eaten by a menu first (no plain ⌘B/⌘I exists in `AlpBrowserApp`).
3. `WebViewContainer.swift`: `NSEvent.addLocalMonitorForEvents` handler capturing `self` weakly inside an `NSView` subclass; `deinit` touches a stored property. Runtime: clicking each split pane moves the focus ring and the keyboard focus.
4. `PeekAndOverlaysView.swift`: `PeekPageState` Combine KVO (`publisher(for: \.title)` etc. on `WKWebView`), the `[AnyCancellable]` array literal, `TabItem(id:...)`.
5. `BrowserState.swift`: `live?.title.flatMap { ... }` optional chain in `expandPeekToFullTab`, `pruneSplit` ordering, the new timer closure (same shape as the existing ones), `markTabActive` use from `addSplitPane`/`focusSplitPane`.
6. `MainBrowserWindow.swift`: `$browserState.splitRatio` binding from an `@EnvironmentObject`, `onTapGesture(count: 2)` combined with the `DragGesture` on the divider (check double-click does not block dragging).
7. Callers of the removed API: I grepped and updated every `discardSnapshot` and `hibernateTab` call; a build will confirm none was missed.
8. Everything from runs 3–5's lists still stands.

## Still remaining
- Run-time checks from runs 3–5 (ad-block compile at launch, boosts, double window on external URLs, CRX flows against the real Web Store).
- Split: 3 and 4 pane layouts have no draggable dividers (equal split only; the 2-pane case is the resizable one). Dragging a tab into a pane is not implemented.
- Peek: no "open in new window / copy link" actions; no persisted peek.
- Hibernated tabs have no placeholder while reloading.
- Pop-up restyle correction (needs the owner's own description). Note editor still has no live markdown styling.
- Hibernation memory numbers above are unmeasured; the "0 MB" claim is a design target until step 2–4 are run.

## Needs your decision
1. **Auto-hibernate defaults**: the setting defaults to 5 minutes and, since it was never wired before, it now actually kills background pages after that time (they reload on return, losing scroll/form state). Keep the default, or default to Never / longer?
2. **Snapshot-based hibernation as written in the parity checklist**: I removed the cached snapshots because nothing displayed them. If you want a placeholder image while a hibernated tab reloads, it should be stored on disk (compressed), not held in memory. Say if you want that.
3. **Zip policy**: any `..` component is refused, even one that stays inside the folder (e.g. `a/../b`). Real extensions don't ship that. Zip64 archives are refused.
4. **Pane cap** of 4 in Split View (my choice).
5. Still yours from earlier runs: CRX2 handling, Web Store countersignature, extension permission prompt, `archivedTabs` cap, two Settings UIs, sync crypto,
   `.handlesExternalEvents` fix, git history, `AlpOCIBridge.m`/`ALP_REBRANDING_MANIFEST.md`, favicon policy, OCI daemon deployment, icon/PSD authorship.
