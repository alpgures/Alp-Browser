# Claude Run 9 Summary

**Nothing was built, compiled or run.** Linux box, no Swift toolchain; the Mac build is toolchain-blocked (manifest link
failure, not a code error). Every Swift change below, including the new tests, is unbuilt and untested. Nothing was
committed or pushed. `AlpOCIBridge.m`, `ALP_REBRANDING_MANIFEST.md`, `/home/ubuntu/arc-reference`, the OCI daemon and
`Server/alp_cloud_daemon.py` were not touched. I did not study the Arc binary. No sync crypto (key derivation, salt,
AES-GCM calls) was changed, and none of the owner-decision items were changed.

## What I changed

### 1. Split view: keyboard pane moves and ↑/↓ resize
- `Services/SplitPaneLayout.swift`: generic `swappingNeighbour(_:index:forward:)` (swap with the next/previous element, nil at either end, no wrap).
- `Services/BrowserState.swift`: `moveFocusedSplitPane(forward:)` swaps the focused pane with its neighbour in `splitPaneTabIDs`. The pane
  **keeps its size**: 2 panes use `splitRatio = 1 - splitRatio`, 3–4 panes swap the same two entries of `splitFractions`. Focus stays on the moved pane.
  It does nothing at the ends and saves with `scheduleSave()` like a drag.
- `AlpBrowserApp.swift`: Tab menu items **Move Focused Split Pane Forward/Backward (⌃⌘] / ⌃⌘[)** and **Grow (Up) / Shrink (Down) (⌃⌥↑ / ⌃⌥↓)**.
  These call the existing `resizeFocusedSplitPane`, so the 3% step, the 12% minimum and the 20–80% bounds are untouched. I checked the existing
  shortcuts: ⌘⌥[ ] is pane focus, ⌘[ ] is back/forward, ⌃⇧=/-/\ is split add/close/direction, ⌃⌥←/→ is resize. ⌃⌘[ ] was unused.
- `Tests/.../SplitStateTests.swift`: `testSwappingNeighbourMovesOneStepAndStopsAtTheEnds`.

### 2. Command Bar (⌘T) completeness (look unchanged)
Gaps found: no space switching; only 8 actions (no hibernate, peek, import, sync, library, back/forward/reload, pin, favorite, close, find, capture,
mini window…); typed queries rarely reached the actions because the list was capped at 6 rows and filled by tabs; matching was one raw substring;
row ids were `UUID()` per render, so hovering rebuilt the rows; `suggestions` was recomputed several times per render.
- `Views/CommandBarView.swift`:
  - New `availableActions(query:)`: split (add/exit/close pane/direction/focus/move), back/forward (only when possible), reload, copy URL, find, capture to
    easel, peek current page, boost, favorite toggle, pin toggle, close tab, hibernate background tabs, mini window, next/previous space, new space, new folder,
    toggle sidebar, theme, Library + Downloads/Media/Archive/Boosts/Easels & Notes, new easel/note, sync now, import from Arc, settings. Only what applies right now is offered.
  - **Switch to Space** rows (typing a space name, or "space" + part of a name; the active space is skipped).
  - Typing an address adds an **Open in Peek** row. Tab rows show a note/easel icon for those tab kinds.
  - Multi-word matching (every word must match), up to 8 rows (3 tabs, 2 spaces, then actions). Empty query is as before (4 tabs + one action row).
  - Stable row ids; the list is built once per render (`barContent(items:)`); the key monitor still reads the live list.
- Not changed: the pop-up's look, search engine (still Google), ⌘L behaviour.

### 3. Sidebar wiring audit
Wired and fine: favorites grid, pinned tree, Today list, space pager/switcher, Library Downloads / Media (live scan, refreshes when a download finishes), Boosts
(toggle, open site, delete), Easels and Notes (open, new, delete, search), Archive (open, filters, search), media mini-player.
Gaps found and fixed:
- **No way to add or remove a favorite** (favorites only ever came from the Arc import). `BrowserState.toggleFavorite(tabID:)`; tab menu **Add to Favorites**, favorite tile menu **Remove from Favorites / Copy URL / Unload Tab**, Command Bar action.
- **Spaces could not be renamed or deleted.** `renameSpace`, `deleteSpace` (never the last one; open web tabs go to the Archive first; web views are torn down), space-icon context menu **Rename Space… / Delete Space…** (confirmation). "New Space" now goes through `createSpace()` (switches with the proper transition and closes a peek).
- **Folders could not be created, renamed or deleted** (only imported ones existed). `createFolder`, `renameFolder`, `deleteFolder` (tabs stay pinned in the folder's place); "+" menu **New Folder**, folder context menu **Rename Folder… / Delete Folder (Keep Tabs)**.
- Pinned tab that navigated away had no way back: `resetPinnedTabToHome` existed with no caller. Tab menu now has **Back to Pinned Page**; also **Open in Split View**.
- Archive entries could not be removed: `removeArchivedTab`, `clearArchive`; Archive row menu **Open in New Tab / Copy URL / Remove from Archive / Clear Archive…** (confirmation). `archivedTabs` is still not capped.
- Library always opened on Archive and `alp://downloads`, `alp://notes`, `alp://canvases`, `alp://archive` and `chrome://downloads` just opened it: new `BrowserState.openLibrary(section:)` (also un-collapses the sidebar) now selects the section; the Library view consumes `requestedLibrarySection` on appear.
- Files: `Services/BrowserState.swift`, `Views/SidebarView.swift`, `Views/SidebarLibraryView.swift`.
- Left as is: `BrowserState.selectedLibrarySection` / `LibrarySection` (the old 5-case enum) is unused by any view; I did not delete it. Boost rows cannot be edited from the Library (the editor needs a page of that site).

### 4. Sync robustness (no crypto, no daemon protocol change)
Findings, all fixed unless listed under "Still remaining":
- **Silent overwrite between machines.** Push was an unconditional PUT: a second Mac (or a fresh install with a default store) replaced the cloud vault. Now the client does a GET first and compares the SHA-256 of the cloud blob with the fingerprint this Mac saved after its last successful upload/download (`Vaults/<id>.synced-digest`, local only, never synced). Different, or none yet while a vault exists, means **conflict**: nothing is uploaded and Settings says so, with **Replace Cloud Copy** (confirmation) and **Restore from Backup**. Uses only the daemon's existing `GET`/`PUT`.
- **Restore could lose local data.** It replaced everything with no backup, applied the cloud copy's own `syncConfig` (endpoint, vault name, auto-sync) over this Mac's settings, and when the server was unreachable it silently "restored" the older local cache and said so. Now: a pre-restore snapshot `store.pre-restore-<time>.json` (newest 3 kept) is written next to `store.json`; this Mac's `syncConfig` is kept; an unreachable server is an error and changes nothing; a vault with zero spaces is refused; a separate, explicit **Restore from This Mac** button reads the local encrypted copy. Restore asks for confirmation.
- **Path traversal via vault name.** The vault id was concatenated into a local file path and a URL, and it also arrives from a synced store. Now validated to the daemon's own rule (`[a-z0-9_-]{1,128}`, case-insensitive) before any path or request.
- **Errors were swallowed or wrong.** `try?` hid network errors; every push failure said "Backed up to Local Encrypted Vault"; decrypt/decode failures during restore said "Restored from local encrypted vault"; the Settings status dot was always green. New `AlpSyncError` with plain messages (no internet, server unreachable, server error code, too large, vault damaged, disk full, invalid address/vault name, nothing to back up). `BrowserState.syncProblem` / `syncHasConflict` drive an orange status line and the headline in Settings; conflicts toast even for the background sync; failures toast for manual syncs.
- **Oversized vault.** Checked before upload against the daemon's 15 MiB limit (message says it is still saved here); a 413 is explained; downloads are refused above 15 MiB (via `Content-Length` and a running count). The vault JSON is no longer pretty-printed (smaller; the decoder does not care).
- **Corrupt local vault.** Never deleted or overwritten by a failed read; reported as "damaged or made with a different vault name, nothing was changed".
- **Partial failures.** Local encrypted copy is written first (now a real error if the disk is full, before anything is uploaded); `lastSyncedAt` only moves on a real success; the fingerprint is written only after a successful PUT or GET.
- **Overlapping syncs** (launch auto-sync + manual button) are serialised with an in-flight flag.
- **Local daemon auto-start** kept the process handle so repeated failed syncs no longer spawn a new python each time; stdout/stderr go to the null device (an undrained Pipe can eventually block it); it waits up to ~2 s for `/health` instead of a blind 0.5 s.
- Endpoint trimmed of spaces and trailing slashes and must be http(s) with a host. `refreshSyncStatus` no longer says "Encrypted & Synced" just because `/health` answered.
- Files: `Services/AlpSyncService.swift` (rewritten around the same, untouched `deriveSymmetricKey` / `encryptPayload` / `decryptPayload`), `Services/BrowserState.swift`, `Views/SettingsView.swift`.
- `Tests/.../AlpSyncServiceTests.swift` (new): vault-id rule and traversal strings, endpoint cleaning, local-endpoint detection, digest, plain-language messages, push refusing bad settings before any network or disk work. The conflict/restore paths need a daemon and are untested.

## Build risks to check first on the Mac
1. `AlpSyncService.swift`: `for try await byte in bytes` over `URLSession.bytes(for:)`; `nonisolated public static` helpers inside an actor; `AlpSyncError.errorDescription` reading `AlpSyncService.maxVaultBytes` from outside the actor; `PullResult` holds the non-`Sendable` `PersistedBrowserStore` and crosses the actor boundary (warning-level in Swift 5 mode, I expect).
2. `BrowserState.swift`: `guard case .folder(var folder) = node` inside `updateFolder` / `dissolveFolder`, the recursive non-escaping `transform` closure, `applyRestoredStore`, `ISO8601DateFormatter` snapshot names, `.dropLast(3)` on a sorted array, `@Published syncProblem`.
3. `CommandBarView.swift`: the nested `act(_:_:_:_:_:)` helper with a defaulted middle parameter plus a trailing closure; closures like `{ bs.createSpace() }` that return a value where `() -> Void` is expected; `barContent(items:)` split from `body`.
4. `SidebarView.swift`: two `.alert` / `.confirmationDialog` modifiers on the `Group`, `.alert` with a `TextField` (macOS 13+) inside `FolderRowItemView`; `SettingsView.swift`: two `.confirmationDialog` modifiers on an `HStack`.
5. `AlpBrowserApp.swift`: four more menu items; `.upArrow` / `.downArrow` with `[.control, .option]`.
6. Everything in runs 3–8's lists still stands.

## Runtime checks (unverified assumptions)
- ⌃⌥↑/↓ and ⌃⌘[ ] reach the menu items while a web view or note has focus; moving a pane keeps focus and size in 2, 3 and 4 panes, both orientations, and survives a relaunch.
- Command Bar: typing "space", a space name, "split", "hib", "down", an address (Peek row), and each action actually runs and closes the bar; rows no longer flicker on hover.
- Sidebar: add/remove favorite, rename/delete space (tabs appear in Archive), new/rename/delete folder, Back to Pinned Page, Open in Split View, alert text fields get focus.
- Sync, against a local daemon (`python3 Server/alp_cloud_daemon.py`): first sync of a fresh store over an existing vault must pause with the conflict message; Restore then Sync must work and write a `store.pre-restore-*.json`; stop the daemon mid-sync and check the message and that nothing changes; hand-damage `Vaults/primary.enc` and try Restore from This Mac.

## Still remaining
- "Automatically back up changes in the background" only runs once, at launch. There is no periodic or change-triggered sync. Adding one means more conflict checks per sync; I did not add it unasked.
- No merge on conflict: the user picks cloud (restore) or this device (replace). A real merge needs per-item timestamps the model does not have.
- Restore does not tear down live web views of tabs that disappear (they are released with the pool as usual).
- The Settings text still says "zero browsing history or unencrypted data ever leaves your device" while the key is derived from the vault name (run 3 note). Untouched, owner's call.
- Runtime checks from runs 3–8; no persisted peek; hibernated tabs have no placeholder; pop-up restyle still needs your description.

## Needs your decision
1. **Move-pane shortcut ⌃⌘[ / ⌃⌘]** and **↑/↓ aliases ⌃⌥↑/↓** are my picks.
2. **Conflict policy:** the client refuses to overwrite a cloud vault it has not seen. A brand-new Mac with an existing vault therefore gets a prompt instead of silently overwriting. Say if you would rather it auto-restore.
3. **Deleting a space archives its open tabs but removes its pinned tabs and folders** (confirmation dialog says so). Re-importing from Arc would bring an imported space back, since the import merges by Arc id.
4. **Command Bar size:** up to 8 rows (was 6) so actions are reachable; say if you want it back to 6.
5. Still yours from earlier runs: replace-everything import option, first-launch Start tab, import limits and URL allow-list, resize step, extensions staying in Arc's folder, Peek "new window", dropped-on pane's old tab, 12% / 20–80% bounds, auto-hibernate default, hibernation placeholder, zip policy, 4-pane cap, CRX2, countersignature, extension permission prompt, `archivedTabs` cap, two Settings UIs, sync crypto, `.handlesExternalEvents`, git history, `AlpOCIBridge.m` / `ALP_REBRANDING_MANIFEST.md`, favicon policy, OCI daemon deployment, icon/PSD authorship.
