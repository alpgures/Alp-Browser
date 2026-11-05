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

- **Arc:** The owner reports Arc warns on ⌘Q. Exact wording, layout, buttons, whether a second ⌘Q confirms, whether
  there is a "don't ask again"/Settings toggle, and whether it names tabs/spaces: **unknown — needs owner
  screenshot/description.** No public source for the wording was reachable in the run that built this.
- **Alp Browser now:** `applicationShouldTerminate` (`AlpBrowserApp.swift`) catches every quit route. The first
  request cancels the quit and shows an in-window card (`QuitConfirmationView.swift`): Alp Browser icon,
  "Quit Alp Browser?", a line naming open tabs and spaces, **Cancel** (Esc, click outside) and **Quit** (Return),
  and "Press ⌘Q again to quit". ⌘Q or Quit while the card is up quits. Settings > General has "Warn before quitting"
  (default on). System shutdown/restart/log-out are never blocked. Sessions save in `applicationWillTerminate` as before.
- **Source:** owner report only; design is a best guess.
- **Status:** needs-verification. The wording, the second-⌘Q confirm and the settings toggle are our assumptions.
  Branding: the card uses `NSApp.applicationIconImage` (the Alp icon in effect), so no Arc logo can appear here.
  The "Arc logo flash" from APP_HISTORY_NOTES could not be tested here (no Mac); a source grep found no Arc logo reference in the Swift code, so it was likely from the pre-rewrite tree. Confirm on a Mac.

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
