# Arc Behavior Audit

Checklist of how Arc behaves, as observed by a user, versus what Alp Browser does. Future runs work through it.

**Rules.** Sources are only: the owner's screenshots/descriptions, Arc's public documentation, public community
write-ups, and using the app as a user. Never Arc's binary, resources or any decompiled form. Where a behavior
cannot be sourced, the entry says `unknown — needs owner screenshot/description`. Nothing here is invented.

**Sourcing caveat (run 17):** web access was not available, so entries citing "Arc help documentation" are from the
author's recollection of public docs and were NOT re-fetched. Re-check each against the live docs before marking `matched`.

**Status values:** `matched` (verified against a source) · `needs-verification` (implemented, but Arc's exact
behavior or our result is unconfirmed) · `known-gap` (Arc does something we do not, or the reverse).
Nothing is `matched` yet where it needs a real Mac build; CI cannot run the UI.

---

## 1. Quit warning (⌘Q, Alp Browser > Quit, Dock > Quit)

- **Rules update (run 18, 2026-11-05):** per the clean-room reframe in `CLEAN_ROOM_REWRITE.md` rule 1, behavior and
  user-visible strings read from Arc.app's string tables/binary may be matched exactly. Code is never copied.
- **Mechanism — SOURCED:** Arc drives quitting with `applicationShouldTerminate` + `handleTerminateReply(_:allowTerminateLater:)`
  (deferred reply).
- **Second ⌘Q quits immediately — INFERRED** from the `allowTerminateLater` signature (first ⌘Q shows the dialog and
  defers; a second ⌘Q while it is up quits). Not observed directly. Alp implements it by returning `.terminateCancel`
  on the first ask and `.terminateNow` while a card is up (same observable behavior, no `terminateLater` run-loop mode).
- **Downloads-in-progress alert — SOURCED (exact):** title "Downloads in progress"; body "There are downloads in
  progress. Closing the application will cancel them."; buttons Cancel (cancels the quit) and Quit (quits, cancelling
  the downloads). Shown before the generic dialog, and even when "Warn before quitting" is off. Arc also cancels an
  in-progress auto-update download on quit; Alp has no updater, so nothing to cancel.
- **Generic quit confirmation — partly SOURCED:**
  - Suppression button "Quit, and don't ask again" — SOURCED (exact). Quits and turns the warning off.
  - Settings label "Warn before quitting" — SOURCED (exact). Key `alp_warn_before_quitting`, default on.
  - Title ("Quit Alp Browser?") and body (open tab/space count) — **UNSOURCED.** Arc composes them at runtime, so the
    text could not be recovered from its code. Run 17's best guess is kept. Screenshot Arc's dialog for a pixel-perfect match.
- **Alp Browser now:** `applicationShouldTerminate` (`AlpBrowserApp.swift`) catches every quit route. Active downloads
  (`DownloadTracker.hasActiveDownloads`, live transfers only; finished/failed ones are not counted) show the downloads
  alert; otherwise "Warn before quitting" shows the confirmation card with Cancel, Quit and "Quit, and don't ask
  again". Both are `QuitConfirmationView.swift`. Running downloads are cancelled in `applicationWillTerminate`.
  System shutdown/restart/log-out are never blocked.
- **`NSQuitAlwaysKeepsWindows` — SOURCED** (Arc has `arc_quitAlwaysKeepsWindows`): quitting keeps windows for restoration.
  Alp already saves and restores its session, so no change.
- **Status:** needs-verification on a Mac (UI cannot run in CI).

## 2. Command bar (⌘T, ⌘L)

- **Arc:** ⌘T opens a centered command bar for search/URL/commands and opens the result in a new tab; ⌘L opens it
  for the current page's URL and navigates the current tab. (Arc help documentation.)
- **Alp Browser:** `openCommandBar(prefilledWithCurrentURL:)`; ⌘T centered, ⌘L prefilled and anchored under the URL pill.
- **Status:** needs-verification (suggestion ranking, result types, animation timing not compared). New tab is
  just the command bar (run 14 reverted the start page).

## 3. Sidebar hide / reveal

- **Arc:** ⌘S toggles the sidebar; with it hidden, moving the pointer to the window's left edge slides it out
  over the page and it retreats when the pointer leaves. Traffic lights follow the sidebar.
- **Alp Browser:** ⌘S toggle; 10 pt left-edge hover strip peeks the sidebar; traffic lights fade with it (0.18 s).
- **Status:** needs-verification. Edge strip width, hover delay and spring timings unknown — needs owner description.

## 4. URL dropdown (command bar anchored to the URL pill)

- **Arc:** clicking the URL pill / ⌘L shows a compact bar under the pill rather than a centered one.
- **Alp Browser:** `commandBarAnchored` renders it under the pill and keeps a collapsed sidebar peeked meanwhile.
- **Status:** needs-verification (dimensions, copy-URL affordances unknown — needs owner screenshot).

## 5. Downloads

- **Arc:** downloads are listed in the Library and signalled in the sidebar; two-finger swipe reveals the Library
  (per owner, APP_HISTORY_NOTES).
- **Alp Browser:** `DownloadTracker` + Library downloads section; trackpad gesture reveals Library.
- **Status:** needs-verification. In-progress indicator, "Show in Finder" and auto-clear behavior unknown — needs owner screenshot.

## 6. Top-bar alignment

- **Arc:** window buttons, nav buttons and the URL pill share one horizontal centre line.
- **Alp Browser:** `AlpWindowChrome.alignTrafficLights` aligns the traffic lights to `AlpTopBarMetrics.centerY`.
- **Status:** needs-verification on a real Mac (runs 12–13 tuned it by eye; no pixel comparison available).

## 7. Peek

- **Arc:** Shift-clicking a link (and links from some other surfaces) opens it in a floating preview over the
  page, with options to open it in a tab or dismiss. (Arc help documentation.)
- **Alp Browser:** `PeekSession` overlay; Esc / ⌘W dismiss.
- **Status:** needs-verification. Trigger gestures, button set and animation timing not compared.

## 8. Split View

- **Arc:** tabs shown side by side in one window, adjustable dividers, up to four panes, drag tabs to split.
- **Alp Browser:** ⌃⇧= add pane, ⌃⇧- remove, orientation toggle, resize/move/focus shortcuts, 3–4 pane fractions.
- **Status:** needs-verification. Arc's shortcut set and drag-to-split edge zones: unknown — needs owner description.

## 9. Hibernation / archiving

- **Arc:** inactive tabs are put to sleep to free memory; Today tabs are archived after a set period
  (12 hours by default; options up to 30 days, per Arc's settings).
- **Alp Browser:** snapshot-based hibernation after `autoHibernateMinutes` (default 5) and auto-archive after
  `autoArchiveHours` (default 12).
- **Status:** archive default matched; **known-gap / unknown** for the sleep delay: Arc's idle sleep time is
  not confirmed here — needs owner description. Our 5-minute default is a design choice, not a copy.

## 10. Little Arc equivalent (Mini Alp, ⌘⌥N)

- **Arc:** links opened from other apps appear in a small floating window with a lightweight bar and an
  option to move the page into a space. (Arc help documentation.)
- **Alp Browser:** `MiniAlpWindowController`, floating panel, "Expand to Space" menu; external http(s) links route here.
- **Status:** needs-verification. Window size, auto-close behavior and the "Move to Space" wording unknown — needs owner screenshot.
