# Claude Run 1 Summary

Nothing was built or compiled (Linux, no Swift toolchain), and nothing was committed or pushed.
This was a short run that covered only the two unfinished-goal items.

## Reference material
`/home/ubuntu/arc-reference/Arc.app/Arc.app` was incomplete this run. It held only `Info.plist`,
`PkgInfo`, a stub framework file and an `Icon` entry, with no binary and no resources. I could not study
Arc's real pop-up. The new-tab pop-up changes come from Arc's publicly known look and the existing tree,
so a later run should recheck them against the real reference once the copy is complete.

## Uncommitted changes from the previous agent
I reviewed these and kept them as they were:
- `AlpModels.swift`: `simplifiedDomain` returns "Extension" for `chrome-extension://` URLs.
- `BrowserState.swift`: sync status text is generic (no daemon error text shown). The fallback first-launch
  spaces now include a `https://alpbrowser.app/start` tab in Personal.
- `PeekAndOverlaysView.swift`: the theme picker is 580 wide.

## What I changed
- `Views/CommandBarView.swift` (new-tab pop-up restyle):
  - Wider panel (620 pt) with an 18 pt corner radius.
  - Translucent material background with a dark tint and a faint tint from the space colour.
  - Positioned in the upper part of the window instead of near the centre.
  - Larger 18 pt borderless input; the placeholder is now "Search or Enter URL…". The `info.circle` icon is removed.
  - A hairline separator now sits under the input row, and rows are 38 pt tall with a 9 pt corner radius.
  - The primary row now shows the raw query with a trailing "Open Link ↵" or "Search Google ↵" label.
  - On ⌘L the pre-filled URL is selected, so typing replaces it.
  - New `trailingLabel` field on `CommandSuggestion`.
- `Views/SidebarLibraryView.swift` (library fixes):
  - The Downloads folder was scanned on every view update; it is now loaded off the main thread into `@State` and refreshed on appear and when the section changes (`reloadDownloads()`).
  - The Archive "Filter" button was a no-op; it is now a menu (All Time, Last 24 Hours, Last 7 Days, Older).
  - The search box is cleared when you switch sections.
- `Views/PeekAndOverlaysView.swift`: the theme picker title "Arc Space Theme Studio" is now "Space Theme Studio" (trademark in a UI string).

## Needs the owner's decision (top priority)
- **`Sources/AlpOCIBridge/AlpOCIBridge.m` (2,668 lines) is still in the tree and is not clean-room.**
  - Its header says it is an in-process bridge injected into the original Arc.app binary.
  - It rebrands Arc's strings, hooks keychain calls, forges Firebase auth tokens, routes "Alp Max" AI to Claude Code on OCI, and contains `arc://` handling.
  - It is not a SwiftPM target, so it does not affect the build.
  - It breaks the hard rules and the "no AI feature / no OCI" decisions, and commit 2c6d338 claims the legacy sources were removed.
  - I recommend deleting it (`git rm`) before any push. I did not delete it myself. `AlpSyncService.swift` already covers vault sync in Swift.
- `Server/oci_arc_cloud_daemon.py` is the other Arc/OCI-named file. It was not audited this run.
- User-visible "Import from Arc" strings in `SettingsView.swift`, `AlpBrowserApp.swift` and `BrowserState.swift` are nominative references for the importer feature. Confirm the owner is OK with them.

## Build risks to check first on the Mac
1. `CommandBarView.swift`: `.fill(.ultraThinMaterial)` inside a `ZStack` of `RoundedRectangle`s. Also `browserState.activeTheme.primaryColor.swiftUIColor`, which should exist (`RGBAColor.swiftUIColor`, AlpModels.swift:83).
2. `SidebarLibraryView.swift`:
   - The `Menu` with `.menuStyle(.borderlessButton)`, `.menuIndicator(.hidden)` and `.fixedSize()`.
   - The new `ArchiveFilter` nested enum.
   - `downloadsListView` now starts with `let files` and uses `return`.
   - `DispatchQueue.main.async { downloadFiles = … }` mutating `@State` from an escaping closure.
3. `.onChange(of:)` is used in its two-parameter form, which is fine for macOS 14.

## Remaining work (not started)
- Library "Media" section is a placeholder. Downloads show no in-progress state, and the list doesn't refresh when a download finishes.
- Walk the rest of the CLEAN_ROOM_REWRITE.md parity checklist against the code: Boosts 2.0, Easels and Notes depth, Little Arc equivalent, WKContentRuleList ad blocking, the Chrome Web Store extension install flow, and the performance bar.
- Audit `Tests/` and the `Server/` daemon for Arc-derived content.
