# Claude Run 11 Summary

**Nothing was built, compiled or run.** Linux box, no Swift toolchain; the Mac build is toolchain-blocked (manifest link
failure, not a code error). Every Swift change below is unbuilt and untested, and no tests were added. Nothing was committed or
pushed. `AlpOCIBridge.m`, `ALP_REBRANDING_MANIFEST.md`, `/home/ubuntu/arc-reference`, the OCI daemon and
`Server/alp_cloud_daemon.py` were not touched. I did not study the Arc binary. Sync crypto, the daemon protocol, auto-sync timing
and every owner-decision item are unchanged.

## What I changed

1. **Fingerprint after a local restore** (`Services/BrowserState.swift`, `restoreVaultFromLocalBackup`): after `applyRestoredStore`, `lastSyncedFingerprint` is set to the restored state, the same as the cloud restore. A local restore no longer triggers an immediate background upload. The conflict check lives in `AlpSyncService.pushStore` (GET and digest compare), which I did not touch. The next real edit still goes through it, so a cloud vault that changed since the backup is not overwritten.
2. **Volatile fields out of the fingerprint** (`Services/BrowserState.swift`, `syncFingerprint` plus two new private static `normalisedForFingerprint` helpers, for `TabItem` and `SidebarNode`):
   - On a copy of the store, for every tab in favorites, pinned nodes (recursing into folders) and today tabs, `lastActiveAt`, `isLoading`, `estimatedProgress`, `isPlayingAudio` and `isHibernated` are reset to constants before hashing.
   - These are the only persisted fields I found that change on ordinary browsing. I checked every persisted type (`TabItem`, `FolderItem`, `AlpSpace`, `PageMod`, `AlpCanvas`, `AlpNote`, `ArchivedTab`, `AlpSyncConfig`, the store itself).
   - Kept in the fingerprint: URL, title, pinned/muted state, folder expansion and everything else, since those are real changes. Stored and uploaded data is unchanged; only the hash input changes.
   - Side effect: a store with only volatile differences is now seen as unchanged, so e.g. `lastActiveAt` alone will not trigger a push. It will go out with the next real change.
3. **Library Boost row, tap vs toggle** (`Views/SidebarLibraryView.swift`, `boostsListView`): the code reading could not settle whether a parent `onTapGesture` beats the child `Toggle` for the click. I did not leave it to chance. The tap-to-edit gesture (and its `contentShape`) now covers only an inner `HStack` holding the domain/summary text and the spacer. The `Toggle` is a sibling outside it, so the switch cannot open the editor. The context menu stays on the whole row. Side effect: clicking the row's padding around the switch no longer opens the editor; only the text area does.
4. **Compile-risk sweep, round 2**: I re-read the code behind the runs 6–10 risk lists. I found **no definite compile errors and made no changes** for this item. Details below.

## Compile-sweep result (item 4)

Read with no definite error found:
- `AlpSyncService.swift`: the `nonisolated static` helpers in the actor, `bytes(for:)` loop, `Equatable` error enum, `PullResult`.
- `BrowserState.swift`: `updateFolder` and `dissolveFolder` (the non-escaping closure passed down recursively is legal), `performArcImport` (`if case ArcImportError.notFound = error` is valid), `applyRestoredStore`, `allStoredTabIDs`, the debounce `Task`.
- `CommandBarView.swift`: the `act(...)` helper with a defaulted middle parameter and trailing closure. Closures that return a value where `() -> Void` is expected are legal single-expression closures.
- `NoteMarkdownStyler.swift`: private nested types, the labelled tuple, the nested funcs, the NSString bridging.
- `ZipArchiveScanner.swift` and the `ZipBuilder` test helper, `PaneTabDropTarget` / `TabDropTargetView`, `PeekPageState`, `BoostEditorForm.swift` / `LibraryBoostEditorView`, the new importer `ImportContext`.
- I did not re-read every line of runs 6–10's lists. Items not named here (the `SettingsView` / `SidebarView` alert and dialog modifiers, `AlpBrowserApp` menu items, `resizeFocusedSplitPane`, `dropSidebarTab`, the `NSTextView` subclass in `EaselNoteAndLibraryView`, the `NSEvent` monitor in the pane view, `AlpSidebarImporterTests`) were not re-checked this run, and are not verified.

**Uncertain, left untouched. Check these first on the Mac:**
1. `MainBrowserWindow.swift:289`, `SplitDividerView.onCommit`'s default value `{ BrowserState.shared.scheduleSave() }`. `BrowserState` is `@MainActor` and `SplitDividerView` only has `@State` / `@Binding`, so the struct may not be inferred main-actor. If the compiler reports "call to main actor-isolated … in a synchronous nonisolated context" here, the fix is an optional `onCommit` (default `nil`) called from inside `body` closures. The 2-pane call sites use the default; the 3–4-pane ones pass their own closure.
2. Whether the other View-struct helper methods that touch `BrowserState` (e.g. `availableActions` in `CommandBarView`, which is not on an `@EnvironmentObject` struct) hit the same main-actor rule. The older view code already does this and presumably built, so I expect it is fine.
3. `NoteMarkdownStylerTests`' `NSColor` equality for dynamic system colours (run 7 note).
4. `PersistedBrowserStore` / `PullResult` not being `Sendable` across the `AlpSyncService` actor: expected to be warnings in Swift 5 mode.
5. My new code: `normalisedForFingerprint` has two overloads (`TabItem`, `SidebarNode`) called through `.map { … ($0) }` on typed arrays. This should resolve; if the compiler reports ambiguity, rename one.
6. Everything in runs 3–10's lists that I did not re-read still stands.

## Runtime checks (unverified)
- Boost row: click the switch (it toggles, no sheet) and click the text (sheet opens), including on a row with a long domain.
- Sync: browse for a while without editing anything (switch tabs, load pages, play audio) and confirm no upload follows the 30 s timer. Then rename a tab or space and confirm exactly one upload.
- Local restore: use "Restore from This Mac" and confirm no upload follows. Then change something and confirm the sync still stops with the conflict message if the cloud vault was changed elsewhere.

## Still remaining
- Runtime checks from runs 3–10; no persisted peek; hibernated tabs have no placeholder; the pop-up restyle correction still needs the owner's description.
- The local-restore path still stamps `syncConfig.lastSyncedAt = Date()` (inside `applyRestoredStore`), so the Settings "last synced" time can show a restore as a sync. That predates this run, was not in scope, and I left it.
- A tab's `title` is still in the fingerprint. A page that keeps changing its title (a live counter in the title, for example) can still mark the store changed. The 60 s gap bounds the cost, but it is not normalised, because it is real user-visible data.

## Needs your decision
- Nothing new. All earlier owner-decision items stand (they are listed in runs 6–10, and the "do not change" list in this run's brief).
