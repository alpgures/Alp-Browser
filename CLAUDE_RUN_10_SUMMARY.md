# Claude Run 10 Summary

**Nothing was built, compiled or run.** Linux box, no Swift toolchain; the Mac build is toolchain-blocked (manifest link
failure, not a code error). Every Swift change below is unbuilt and untested, and no new tests were added. Nothing was
committed or pushed. `AlpOCIBridge.m`, `ALP_REBRANDING_MANIFEST.md`, `/home/ubuntu/arc-reference`, the OCI daemon and
`Server/alp_cloud_daemon.py` were not touched. I did not study the Arc binary. Sync crypto and the daemon protocol are unchanged,
and none of the owner-decision items were changed.

## What I changed

### 1. Background sync: change-triggered and periodic (`Services/BrowserState.swift`)
- `scheduleSave()` now also calls `noteStoreChangedForSync()`: a 30 s quiet-period timer (restarted by each change). When it fires it calls `autoSyncIfChanged()`.
- A 10-minute repeating timer (`periodicSyncTimer`, started in `init`) calls the same `autoSyncIfChanged()`.
- `autoSyncIfChanged()` runs the existing `syncNow(silent: true)`, so run 9's checks apply as they were (GET first, compare the fingerprint, stop and prompt on conflict, never overwrite). It only runs when:
  - the toggle is on;
  - no sync is in flight (the run 9 flag);
  - there is no unresolved conflict (`syncHasConflict`), so a conflict is not re-toasted every few minutes;
  - the store has spaces;
  - the content fingerprint differs from the last successful sync;
  - the previous background attempt was at least 60 s ago (otherwise it re-arms the debounce for the remainder). This keeps a failing or offline server from being hit on every edit.
- Fingerprint: SHA-256 of the store JSON (sorted keys) with `syncConfig.lastSyncedAt` blanked, so recording a finished sync does not look like a change. It is stored in memory only and set on a successful push. After "Restore from Backup" (cloud) it is set to the restored state, so a restore does not immediately upload again. The launch sync still always runs (the fingerprint starts nil).
- The toggle is checked both when a change arrives and when the timer fires. Turning it off cancels the pending timer.
- Manual "Sync Now" and "Replace Cloud Copy" are unchanged.

### 2. Restore tears down dead web views (`Services/BrowserState.swift`)
- `applyRestoredStore` records the ids of every stored tab (all spaces plus favorites) before applying the store. Afterwards, for ids that no longer exist, it calls `WebViewPool.destroyWebView` and `forgetTab` and drops them from `recentTabIDs`. A Peek whose source tab is gone is closed.
- Surviving tabs are not touched. Peek and Mini Alp tabs are not in the store, so they are not mistaken for dead tabs (I compare store ids before and after, not the pool's live list).
- Applies to both restore paths (cloud and local backup), since both go through `applyRestoredStore`.

### 3. Library-side boost editing
- `Views/BoostEditorForm.swift` (new):
  - `BoostEditorForm` is the editing controls moved out of `StyleStudioView`: toggle, hidden elements, sliders, invert, tint, font, CSS, JS, Reset, Delete. The page-only buttons ("Snip / Hide Element", "Run on this page now") show only when `pageActions` is non-nil.
  - `LibraryBoostEditorView` loads the `PageMod` by id from `browserState.styles`, edits a draft, writes back to the same entry (`updatedAt`, `scheduleSave`), and calls `commitBoostChanges()` on close so open tabs get the new scripts and CSS. It also has a name field and a Done button, and handles a boost deleted while the sheet is open.
  - There is no second boost format.
- `Views/PeekAndOverlaysView.swift`: `StyleStudioView.editor` now just hosts `BoostEditorForm` with its page actions. Behaviour is meant to be identical. `sliderRow` and `codeBox` moved to the new file.
- `Views/SidebarLibraryView.swift`: clicking a Boost row, or context menu **Edit Boost…**, opens `LibraryBoostEditorView` in a sheet. The domain is not editable (it is the match key).

### 4. Dead code removed (`Services/BrowserState.swift`)
- Deleted `BrowserState.selectedLibrarySection` and the `LibrarySection` enum. Grepped `Sources` and `Tests`: no other reference (`LibraryRailSection` / `requestedLibrarySection` are separate and remain).

### 5. Final clean-room sweep (no file changes needed)
Searched every tracked and untracked file (Swift, tests, scripts, Server, Package.swift, workflow, README, LICENSE, Icons names, the ignored `Alp Browser.app` Info.plist and resource names, `CustomGraphics/`, which is empty) for `Arc` as a word or identifier, `arc://`, `thebrowser`, `Little Arc`, `Arc Max`, `SpaceStyle`, `Firebase`, `/Users/`, `claude`, `OCI`, and Arc-exclusive product wording.
- Outside the two known items, the only remaining hits are nominative importer references that the brief says to leave alone:
  - "Import from Arc" strings.
  - `AlpSidebarImporter.swift` (the data-folder paths, `ArcImportError`).
  - The glue in `BrowserState` (`performArcImport`, `importFromInstalledArcBrowser`, `hasImportedFromArc`).
  - `AlpExtensionManager.importExtensionsFromArc` and its Arc data-folder path.
  - `originalArcID` on `AlpSpace`: a persisted field used to merge re-imports, so renaming it would break saved stores.
  - Importer tests that use `arc://` as input to prove it is rejected.
  - One importer comment, "local Arc.app", in `BrowserState`.
- No Arc strings, `arc://` URLs, bundle ids, hardcoded developer paths or Arc assets remain outside `AlpOCIBridge.m` and `ALP_REBRANDING_MANIFEST.md`. The `Alp Browser.app` bundle in the tree is gitignored.
- Not decidable by grep: asset authorship (PSDs, mountain glyph, run 5's open question) and the studio pad constants carried over in run 4.

## Build risks to check first on the Mac
1. `BrowserState.swift`:
   - `noteStoreChangedForSync(after delay: TimeInterval = BrowserState.syncDebounceSeconds)`: a private static used as a default argument inside a `@MainActor` class.
   - The `Task { @MainActor [weak self] in … Task.sleep … }` debounce.
   - `Self.syncFingerprint` mutating a copy of the non-`Sendable` `PersistedBrowserStore`, and `AlpSyncService.digest(of:)` called from the main actor (it is `nonisolated static`, internal).
   - `allStoredTabIDs()` using `space.allTabs`.
2. `BoostEditorForm.swift`: the `if let pageActions {` shorthand needs Swift 5.7 or later, which is fine on 5.10. `Binding(get: { draft ?? PageMod(domain: "") }, set: { draft = $0 })`. `.onChange(of: draft)` with an optional `PageMod` (it is Equatable) and the two-parameter closure form (macOS 14).
3. `SidebarLibraryView.swift`: `.sheet` attached to the boosts list view inside a sidebar panel, and `.onTapGesture` on a row that also holds a `Toggle`.
4. `PeekAndOverlaysView.swift`: `StyleStudioView` still uses `activeStyle`, `lastApplied`, `currentDomain`, `loadExistingStyle` and `applyLiveStyle`; nothing else should have referenced the removed `sliderRow` / `codeBox`.
5. Everything in runs 3–9's lists still stands.

## Runtime checks (unverified)
- Sync against a local daemon:
  - edit something, wait about 30 s, and confirm exactly one upload and no loop afterwards (`lastSyncedAt` changes but no further PUT);
  - toggle off and confirm nothing uploads;
  - with a second vault changed elsewhere, confirm the background sync stops with the conflict toast once and then stays quiet;
  - confirm Restore does not trigger an immediate upload.
- Restore: with a tab open that is not in the cloud copy, confirm its page stops (audio ends, no process) and that surviving tabs keep their scroll position.
- Boost: edit CSS/JS/sliders from the Library with the site closed; open the site and confirm the new boost applies; confirm the page panel still works as before (zapper, run now, reset, delete) and that tapping a row's switch still toggles instead of opening the editor.

## Still remaining
- Runtime checks from runs 3–9; no persisted peek; hibernated tabs have no placeholder; the pop-up restyle correction still needs the owner's description.
- Auto-sync fingerprint includes volatile tab fields, if any are persisted (for example last-active times), so ordinary browsing can mark the store "changed". The 30 s debounce and 60 s gap bound the cost, and a sync of an unchanged-in-substance store is harmless. If it proves chatty, normalise those fields in `syncFingerprint`.
- A restore from "This Mac's backup" (local) does not set the fingerprint, so the next background sync will push it (after the usual conflict check).

## Needs your decision
1. **Auto-sync timing:** 30 s after the last change, a 10-minute periodic check, and at least 60 s between background attempts. Those are my choices.
2. **Background sync stops after a conflict** until you resolve it in Settings (Restore or Replace). Say if you would rather it keep checking quietly.
3. The nominative "Import from Arc" wording, and the two untouched files (`AlpOCIBridge.m`, `ALP_REBRANDING_MANIFEST.md`), are still yours.
4. Still yours from earlier runs: replace-everything import option, first-launch Start tab, import limits and URL allow-list, resize step, extensions staying in Arc's folder, Peek "new window", dropped-on pane's old tab, pane bounds, auto-hibernate default, hibernation placeholder, zip policy, 4-pane cap, CRX2, countersignature, extension permission prompt, `archivedTabs` cap, two Settings UIs, sync crypto and the Settings privacy text, `.handlesExternalEvents`, git history, favicon policy, OCI daemon deployment, icon/PSD authorship, conflict policy, space-deletion behaviour, Command Bar size, move-pane shortcut.
