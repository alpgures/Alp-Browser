# Claude Run 2 Summary

Nothing was built (Linux, no Swift toolchain). Nothing was committed or pushed. `AlpOCIBridge.m` and `/home/ubuntu/arc-reference` were not touched.

## Not done, on purpose: studying the real Arc.app
The brief asked me to study Arc's real pop-up and sidebar library and correct run 1's restyle against them. I skipped that. CLEAN_ROOM_REWRITE.md hard rule 1 says nothing may come from Arc's binary, resources or any decompiled form. Pulling dimensions, strings or layout out of the copied app would taint the rewrite, and the rewrite exists to remove that exposure.
- Run 1's pop-up and library restyle is unchanged.
- To correct it, someone can review the running app visually and give me the target look in their own words, or the owner can say explicitly that this rule is relaxed.

## What I changed
- `Services/DownloadTracker.swift` (new): an observable object that tracks in-flight `WKDownload`s, with progress through KVO on `download.progress`. It updates only on changes of 1% or more, and bumps `finishedCount` when a download ends.
- `Services/WebViewPool.swift`: the download delegate calls `DownloadTracker` on begin, finish and fail.
- `Views/SidebarLibraryView.swift`:
  - Downloads now show in-progress rows (`ActiveDownloadRow`: progress bar, "x of y · n%") at the top of the list.
  - The list reloads when a download finishes.
  - The Media section is now a thumbnail grid of images, video and audio from ~/Downloads, replacing the placeholder. Thumbnails are downsampled off the main thread (`MediaTile`); a tap opens the file and the context menu has "Show in Finder".
  - The list is scanned to 200 files, with the Downloads list still capped at 25.
- `AlpBrowserApp.swift`:
  - `application(_:open:)` sends http(s) links from other apps to the Mini Alp window, which is the Little Arc equivalent. The Info.plist already registers http and https.
  - Reopening Mini Alp closes the previous window, and `isReleasedWhenClosed` is set to false.
- `Services/AlpExtensionManager.swift`: `installFromWebStore(_:)` takes a Web Store link or a 32-letter ID, downloads the .crx, strips the CRX2/CRX3 header, unzips it with `/usr/bin/ditto`, and installs it through the existing `installExtension(from:)`.
- `Views/SettingsView.swift`: the Extensions tab has a "Chrome Web Store link or extension ID" field with an Install button.
- `Services/BrowserState.swift`: `chrome://settings`, `extensions` and similar open Settings. `chrome://downloads`, `history` and `bookmarks` open the Library. Other `chrome://` URLs open Settings.

## Build risks to check first on the Mac
1. `DownloadTracker.swift`: `progress.observe(\.fractionCompleted)` calls back off the main thread and hops to `@MainActor` with `Task`. Check for Swift 6 sendability warnings or errors.
2. `SidebarLibraryView.swift`:
   - `@ObservedObject private var tracker = DownloadTracker.shared`. A main-actor singleton used as a property default may need `@MainActor` isolation.
   - `MediaTile.loadThumbnail` is `nonisolated static` and is called from `Task.detached`.
   - `Self.isMedia` is called inside the background closure in `reloadDownloads`.
3. `AlpExtensionManager.swift`: `nonisolated private static func unpackCRX` is called from `Task.detached` inside a `@MainActor` class. `Data` index arithmetic, `Process` use.
4. `AlpBrowserApp.swift`: SwiftUI `WindowGroup` may also open a new main window on an external URL event, alongside the delegate's `open urls:`. Test by opening a link from another app.
5. Run 1's earlier risks still apply (see CLAUDE_RUN_1_SUMMARY.md): `CommandBarView` material fill, and the `Menu` styling and `ArchiveFilter` in the Library.

## Remaining and for the owner
- Parity items not examined this run: Boosts 2.0 depth, Easels and Notes depth, ad-block rule coverage in `WebViewPool` (a rule list exists), and measured performance.
- Unreviewed for Arc-derived content: `Server/oci_arc_cloud_daemon.py` (the only file in Tests, Server, Package.swift and scripts/bundle-app.sh that matches Arc names) and `scripts/patch-original-arc.sh`. The script's name and contents say it patches the original Arc.app, so it is likely not clean-room.
- `AlpOCIBridge.m` is still awaiting the owner's decision (see run 1).
- `AlpBrowserApp.swift` hardcodes a developer path, `/Users/alpgures/Documents/antigravity/arc2.0/Icons/…`, as the icon fallback. It should go before any push.
