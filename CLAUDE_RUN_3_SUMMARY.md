# Claude Run 3 Summary

**Nothing was built, compiled or run against Swift.** This is a Linux box with no toolchain, and the Mac
build is toolchain-blocked (see the briefing). Every Swift change below is unbuilt and untested.
The only code I executed was the Python daemon (smoke-tested locally on a spare port).
Nothing was committed or pushed. `git rm` staged two deletions; those are staged, not committed.
`AlpOCIBridge.m` and `/home/ubuntu/arc-reference` were not touched. I did not look at the Arc binary.

## What I changed

### 1. Developer path removed
The path `/Users/alpgures/Documents/antigravity/arc2.0` appeared in six Swift/script places, not one. All are gone from `Sources/`, `scripts/` and `Server/`.
- `Services/AlpIconGenerator.swift`: new `bundledIcon(named:)` helper (Bundle.main only). The mask-PNG fallback and the "also set icon on the dev .app" block are removed.
- `AlpBrowserApp.swift`, `Views/SettingsView.swift`, `Services/BrowserState.swift`: icon lookups use `bundledIcon(named:)`. If the app is run unbundled (e.g. `swift run`), the icon is simply not changed.
- `Services/AlpSyncService.swift`: the daemon is launched only from the bundled `alp_cloud_daemon.py` resource.
- `scripts/bundle-app.sh`: `PROJECT_DIR` is derived from the script location, and the daemon is now copied into the bundle's Resources (it was never bundled before, so auto-start could not have worked outside the dev machine).
- Still present, untouched: the same paths inside `Sources/AlpOCIBridge/AlpOCIBridge.m` (awaiting your decision) and personal `file:///Users/alpgures/Downloads/...` URLs in `alp-spaces-export.{json,md}` (see below).

### 2. Clean-room audit
- `scripts/patch-original-arc.sh`: **deleted** (`git rm`). It copied `/Applications/Arc.app`, thinned the Mach-O, injected a dylib and patched Arc's nib and strings, so it is the opposite of clean-room. No other file referenced it.
- `Server/oci_arc_cloud_daemon.py`: **deleted** (`git rm`) and replaced by a standalone rewrite in `Server/alp_cloud_daemon.py`. The old file was not just badly named:
  - It proxied `/v1/ai` to the Claude CLI ("Arc Max"). Removed, per the owner decision to ship no AI feature.
  - It had a hardcoded personal email address as the default account, a pre-provisioned `/v1/auth` endpoint, and a `/v1/spaces/alp` backup route. All removed; the Swift client calls none of them.
  - It used `ARC2_PORT`, `~/.arc2-cloud`, `arc-cloud/` path aliases and "arc-immortal" service names. All removed.
  - The new daemon implements only what `AlpSyncService` uses: `GET /health`, `GET/PUT /v1/vault/<id>`. It has no request logging, a 15 MiB cap, a strict id regex and atomic 0600 writes. Config is `ALP_SYNC_PORT` (default 8788) and `ALP_SYNC_DIR` (default `~/.alp-cloud`).
- `CLEAN_ROOM_REWRITE.md`: the daemon filename in rule 5 is updated.
- Nothing else in `Server/` was touched.

### 3. Parity depth

**Boosts**
- `Services/WebViewPool.swift`:
  - Boosts are now installed as `WKUserScript`s. CSS goes in at document start (no unstyled flash) and custom JS at document end, one script per boost. JS is embedded directly rather than eval'd, so strict page CSPs cannot block it. Scripts are reinstalled on all live tabs by `reapplyBoosts()`.
  - Site matching now uses exact host or subdomain. The old `host.contains(domain)` matched `x.com` against `box.com`.
  - `applyStyle` is now CSS-only. Before, it re-ran the custom JS on every slider tick and every page load.
  - CSS is passed to the page via a JSON string literal.
- `Models/AlpModels.swift`: `PageMod.matches(host:)`.
- `Views/PeekAndOverlaysView.swift` (`StyleStudioView`): rebuilt. It now has:
  - enable toggle;
  - list of hidden elements with undo;
  - saturation, hue and text-size sliders, plus colour tint and a font picker (hue, saturation, tint and text size were in the model but had no UI);
  - custom CSS and **custom JS** editors, with a "Run on this page now" button;
  - Reset and Delete;
  - a "open a web page" guard (before, it could create a boost for `example.com`).
- `Services/BrowserState.swift`: `commitBoostChanges`, `setBoostEnabled`, `deleteBoost` and `removeZappedSelector`; the zapper now goes through the same path.
- `Views/SidebarLibraryView.swift` (Boosts section): a real list with a summary, an enable switch, and Open Site and Delete in the context menu. Before, it had only a toggle.
- Persistence was already in place (`styles` in the store); no model change was needed.

**Easels and Notes**
- `Services/BrowserState.swift`:
  - `openCanvas`/`openNote` select an existing tab instead of opening duplicates.
  - Rename and delete for both (delete closes any open tab); tab titles follow renames.
  - `createNewCanvas`/`createNewNote` now return the id.
  - Closing an easel or note tab no longer adds an `alp://…` entry to the archive.
  - Capture-to-easel (⌘⇧2) fixed. It used to create a canvas but never add the capture, and it stole focus by opening the canvas tab. It now stores a PNG plus a link card in the most recently edited easel, without switching tabs.
  - Easel images are stored in `Application Support/AlpBrowser/CanvasImages` rather than by absolute path to the user's file.
- `Views/SidebarLibraryView.swift`: a new **Notes** section (notes were not listed anywhere before), and "New Easel"/"New Note" buttons. Both lists are searchable, sorted by recent, and have Delete.
- `Views/EaselNoteAndLibraryView.swift` (rewritten):
  - Easel: editable title, a Link card from the clipboard (with an open-in-tab button), a colour menu, resize handle, bring-to-front on drag, and image copy-in.
  - Typing is committed after a 350 ms pause (flushed on disappear), instead of a store mutation and full UI refresh on every keystroke.
  - Images are decoded once, not on every body evaluation.
  - I **deleted ~410 lines of dead code** (`LibraryDrawerView`, `LibrarySheetView`): nothing referenced them, and they duplicated the sidebar Library.
- Known gap: the Note formatting buttons only append markdown at the end. `TextEditor` selection access needs macOS 15, and the target is 14.

**Ad blocking** (`Services/WebViewPool.swift`)
- **The old rule list probably never compiled.** The second rule used `(a|b|c)` alternation, which WebKit content-blocker regexes do not support. The compile error was discarded (`_`), so the list would have been nil and nothing blocked. I can't confirm this without running it; the first rule was also useless (`if-domain` matches the page's domain, not the resource's).
- The new list is generated in Swift (no network): about 105 ad/tracker/pop-under hosts, each a third-party-only rule matching the host and its subdomains, plus a few third-party path patterns and one element-hiding rule for common ad containers.
- It is compiled once per version id (`…v2`) and reused from disk. The old list id is removed.
- Compile errors are now logged with `NSLog`.
- The Settings toggle now applies to open tabs (a page reload is needed); tabs created before the compile finished now get the list.
- Facebook login, YouTube and similar were deliberately not blocked.

### 4. Performance (static review only; nothing measured)
Fixed:
- `currentProcessMemoryMB` was `@Published` and sampled every 5 s. Nothing reads it, so the whole UI re-rendered every 5 s while idle. It is now unpublished and sampled every 30 s.
- `didFinish` took a snapshot of every page load. No view displays snapshots, so it was pure CPU and RAM cost, and snapshots of closed tabs were never freed. The per-load capture is removed (hibernation still captures), and snapshots are discarded on close, archive and delete.
- `FaviconCache.favicon(for:)` is called from view bodies. It read the disk synchronously on the main thread and started a new network request on every refresh for an uncached host. It now loads off-thread with in-flight and failed-host sets.
- Store saves encoded the full pretty-printed JSON on the main thread. Debounced saves now encode and write on a serial background queue; the quit-time save blocks on that queue so ordering is preserved.
- Library downloads scan runs via `Task.detached`.

**To measure on the Mac once the toolchain works:**
1. Cold launch to first interactive window. Check store load/decode size and the Arc-import check that runs at launch (`loadPersistedOrImportFromArc`).
2. Tab switch latency with 5, 25 and 100 tabs. `mutateTab` rebuilds nested arrays and sends `objectWillChange` (twice) on every navigation progress step, so check body evaluations per switch.
3. Sidebar animation (library open/close, collapse, space swipe). Use Instruments' SwiftUI template. `sidebarWidth` is `@Published` on the global `BrowserState`, so a drag re-renders everything. If it stutters, move the width to a local `@State` during the drag and write it at the end.
4. Idle CPU and wakeups with a few tabs (should be about zero now), and with the Library open during a download.
5. `store.json` size growth. `archivedTabs` is unbounded and every closed tab is appended. Decide on a cap (owner call).
6. Ad blocking: page load time and block counts on a few ad-heavy sites, plus rule compile time on first launch.
7. Memory per hibernated tab, to confirm the "0 MB" claim.

## Build risks, check these first on the Mac
The package is `swift-tools-version: 5.10`, so it builds in Swift 5 language mode. That downgrades most run 1/2 sendability worries (DownloadTracker, AlpExtensionManager) to at most warnings. The `@ObservedObject … = X.shared` pattern is already in committed code that GitHub CI builds. I changed one thing for cases where `View` is `@MainActor` under newer SDKs: `isMedia` in `SidebarLibraryView` is now `nonisolated` and called from `Task.detached`. I cannot confirm any of this without a compiler.

New code most likely to hit a compile error:
1. `WebViewPool.swift`: the ad-block section (`lookUpContentRuleList` and `compileContentRuleList` closures with nested `[weak self]`, implicitly-unwrapped `WKContentRuleListStore.default()` used with `?.`), and the multi-line JS string interpolation in `boostUserScripts`.
2. `EaselNoteAndLibraryView.swift`: `onMutate: ((inout AlpCanvasElement) -> Void) -> Void` closures and trailing-closure calls like `onMutate { $0.x += … }`. `NSOpenPanel.allowedContentTypes` needs `UniformTypeIdentifiers` (imported).
3. `PeekAndOverlaysView.swift`: `.onChange(of: activeStyle)` on a `PageMod` (Equatable), and the `Binding` wrappers for tint and font.
4. `FaviconCache.swift`: `Task.detached` returning `Data?`, then `if let diskData` shorthand.
5. `BrowserState.swift`: the `write` closure passed to `saveQueue.async(execute:)` (a Sendable warning is possible).

Runtime checks:
- **Double window (`AlpBrowserApp.swift`) is not resolved.** I could not verify it by inspection. SwiftUI's `WindowGroup` may open an extra main window when an external URL arrives, alongside the delegate's `application(_:open:)`. Test by opening a link from another app. If it happens, the likely fix is `.handlesExternalEvents(matching:)` on the `WindowGroup`, but I did not apply it blind.
- Ad-block: confirm there is no `compile failed` line in the console at first launch, and that a known ad host is actually blocked. This is where I suspect the old list silently failed.
- Boosts: confirm CSS applies on a fresh load (user-script path), edits apply live, and the JS runs once per load.
- The daemon now stores under `~/.alp-cloud`. Existing vaults in `~/.arc2-cloud/vaults` are not read; the client keeps a local encrypted copy and will push again. Move the files if you want the old server copies.

## Still remaining
- Run 1's pop-up restyle correction (waiting for your own description).
- Note formatting does not wrap selections (needs macOS 15 or an NSTextView wrapper).
- No automated tests exist beyond two placeholders; the test target does not import the app target. Boost matching and ad-rule generation would be easy to test once the toolchain works.
- Comments throughout the views still say "matching Arc", "Arc-style", and so on (about 20 places).

## Needs your decision
1. **`SpaceThemeStudioView.swift` header and comments name `SpaceStyleColorPadView`/`SpaceStyleDialView` and "Arc SpaceStyleColorPad".** These read like Arc's internal type names. If the file was written while looking at Arc's code, it needs the clean-room rewrite treatment. I did not touch it. Please check where those names came from.
2. **`AlpOCIBridge.m`** is still in the tree (as instructed). `ALP_REBRANDING_MANIFEST.md` still describes the dylib/`Assets.car` override mechanism and a developer path, and should go or be rewritten with it.
3. **Personal data is tracked in git:** `alp-spaces-export.json` and `.md` hold your actual tab URLs (local file paths, research PDFs). Remove them from the tree before the first push.
4. **The "zero-knowledge" vault is not.** `AlpSyncService` derives the AES key from the vault id with HKDF and a constant salt, and the vault id is also the server filename, so the server can decrypt every vault. The code comments, CLEAN_ROOM_REWRITE.md and Settings text describe it as zero-knowledge. The key should come from a user secret that never reaches the server.
5. **Favicons are fetched from `google.com/s2/favicons`,** which sends every visited host to Google. That conflicts with the privacy goal. An on-device fetch (`/favicon.ico` or `<link rel=icon>` from the page) would avoid it.
6. **Extensions:** `grantAllPermissions` gives every extension every permission, and the Web Store installer does not verify the CRX signature.
7. **"Import from Arc" strings:** still the open question from run 1 (nominative use).
8. Whether to cap `archivedTabs`; whether to keep the `Settings {}` scene alongside the custom settings sheet (two Settings UIs exist).
