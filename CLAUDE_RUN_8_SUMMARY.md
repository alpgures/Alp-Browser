# Claude Run 8 Summary

**Nothing was built, compiled or run.** Linux box, no Swift toolchain; the Mac build is toolchain-blocked (manifest link
failure, not a code error). Every Swift change below, including all new tests, is unbuilt and untested. Nothing was
committed or pushed. `AlpOCIBridge.m`, `ALP_REBRANDING_MANIFEST.md`, `/home/ubuntu/arc-reference`, `Alp Browser.app` and the OCI
daemon were not touched. I did not study the Arc binary. None of the owner-decision items were changed (Peek "new window",
dropped-on pane's old tab, 12% / 20%–80% bounds, auto-hibernate default, hibernation placeholder, zip policy, 4-pane cap,
CRX2, countersignature, sync crypto, `.handlesExternalEvents`, favicon policy, "Import from Arc" wording).

## What I changed

### 1. Split view keyboard resizing
- `Services/SplitPaneLayout.swift`: `keyboardStep` (3% of the split), `nudgedTwoPaneRatio` (clamped 0.2–0.8) and `resizingPane`
  (3–4 panes; trades space with the next pane, or the previous one for the last pane, through the existing `settingPairShare`
  so the 12% minimum holds).
- `Services/BrowserState.swift`: `resizeFocusedSplitPane(grow:)`. 2 panes change `splitRatio`; 3–4 panes write `splitFractions`;
  both call `scheduleSave()` like a drag. Works in both orientations because it is "grow/shrink the focused pane", not a direction.
- `AlpBrowserApp.swift`: Tab menu items **Grow Focused Split Pane (⌃⌥→)** and **Shrink Focused Split Pane (⌃⌥←)**, disabled
  when no split is active. I checked the existing shortcuts: ⌘⌥←/→ is Spaces, ⌃⇧=/-/\ is split add/close/direction, ⌘⌥[ ] is pane
  focus, ⌃1–9 is spaces. ⌃⌥+arrow is unused in the app. macOS only reserves ⌃+arrow (Mission Control), not ⌃⌥+arrow.
- `Tests/.../SplitStateTests.swift`: nudge tests (pane side, bounds, NaN, neighbour trade, last pane, 50 repeated shrinks stop at 12%).

### 2. Drag a tab onto a single viewport starts a split
- `Services/BrowserState.swift`: `dropSidebarTab(_:onPane:)`. In a split it calls `replaceSplitPane` (unchanged); on a single
  viewport it runs the same checks (exists, active space or favorite) and calls `addSplitPane(withTabID:)`, which builds the
  split from the current tab plus the dragged tab and focuses the dragged one. The 4-pane cap and "already a pane" handling are reused.
- `Views/WebViewContainer.swift`: the existing `PaneTabDropTarget` layer is now added to every `ViewportPaneView`, not only
  split panes, and calls `dropSidebarTab`. No pane logic duplicated.
- Not covered by tests (`BrowserState` is a singleton that loads from disk).

### 3. Note editor styling gaps (`Views/NoteMarkdownStyler.swift`)
- `***x***` is bold + italic (new `boldItalicPattern`, run before bold/italic; the three stars on each side are dimmed).
- Ordered lists: `1. `, `12) ` number + delimiter is accent-coloured, bold, monospaced digits.
- Fenced code blocks (``` or ~~~, up to 3 leading spaces): body and fence lines are monospaced with the code background;
  fence lines are dimmed; contents are opaque to every other format. Only a **closed** fence is styled (an unclosed one stays plain,
  like other unbalanced markers); ```` ```x``` ```` on one line stays inline code. A hidden attribute (`alpNoteFence`) marks fenced
  lines. Every restyle does one cheap whole-text line scan (no attribute work) and restyles the edited lines **plus** any line whose fenced
  status the edit flipped (opening/closing/removing a fence), so only those lines are touched.
- Backslash escapes: `\` + ASCII punctuation is masked before any pattern runs (so `\*`, `\#`, `\-`, `\>`, `` \` `` do nothing; `\\` is a literal
  backslash). The backslash is dimmed, the escaped character is plain. Not applied inside fenced blocks or code spans.
- Unchanged: attributes only, saved markdown intact, no undo step, 350 ms debounce, ⌘B/⌘I/⌘E, `EaselNoteAndLibraryView.swift`.
- Known edge: a code span that ends in a backslash (`` `a\` ``) is read as an escaped closing backtick, so it is not styled as code.
- `Tests/.../NoteMarkdownStylerTests.swift`: seven new tests (triple star, ordered list, fence content/opacity/dimming, unclosed and inline fences,
  closing/removing a fence with an edit range that does not include the changed lines, escapes, escaped line starts, doubled backslash).

### 4. Arc importer audit
Review against CLEAN_ROOM_REWRITE.md rule 4 and APP_HISTORY_NOTES.md: `AlpSidebarImporter.swift` parses only the user's own
`~/Library/Application Support/Arc/StorableSidebar.json` and `StorableArchiveItems.json` with original code (plain `JSONSerialization`
walking documented-by-observation key names); no Arc code, assets, strings or binary data. Extension import (`AlpExtensionManager.importExtensionsFromArc`)
only reads the user's own `Extensions/*/manifest.json` and locale files. Findings and fixes:
- **State loss (the serious one).** `importFromInstalledArcBrowser()` is also the menu / Settings action. If Arc data was missing or unreadable it fell
  through to the "default spaces" branch and **replaced all the user's spaces with an empty Personal/Leisure**; a successful import also **replaced**
  every space, favorite and archived tab. Now: first launch behaves as before; a manual import **merges** (adds only spaces whose Arc id is not
  already here, favorites and archive entries whose URL is not already here), leaves the active space alone, and any failure changes nothing and shows a message.
  (`BrowserState.performArcImport`, `installDefaultSpaces`; `importFromInstalledArcBrowser` keeps its name.)
- **Clear errors.** New `ArcImportError` (not found, unreadable, too large, malformed, no spaces) with plain messages shown as a toast; missing Arc is silent on first launch.
- **Zero spaces** used to "succeed" with an empty list and `activeSpaceID = nil`; now `noSpaces`.
- **Large inputs.** File over 256 MB refused; at most 10,000 tabs (and 10,000 archive entries) per import, the rest counted as skipped and reported in the toast;
  nesting capped at 40 levels (cycles were already guarded); titles capped at 300 chars, URLs at 8,192.
- **Quadratic scan removed.** Containers without a child list scanned every item per container, in random dictionary order. Now one parent index in file order (also makes tab order deterministic).
- **Duplicates.** Same URL twice in a favorites row or a space's Today list keeps the first; repeated space ids are skipped; repeated archive URLs are skipped.
- **URLs.** Only `http(s)://`, `file://`, `about:` are imported; Arc's internal pages (`arc://`), `javascript:`, `data:` and empty values are dropped (also keeps arc:// out of the tree).
- **Archive parser** no longer assumes strict id/entry alternation; it takes every element that is an entry dictionary.
- **Corrupt `store.json`.** If the store exists but cannot be decoded, a copy is written next to it (`unreadable-store-<time>.json`) before first-run logic overwrites it.
- `Tests/.../AlpSidebarImporterTests.swift` (new): missing/malformed/truncated files, no spaces, duplicates and unsafe URLs, duplicate space ids, cycles and deep nesting, the 10,000 cap, URL filter.
  Note `importFromArc` still reads the real archive file path for archived tabs, so on a Mac with Arc the archive count in those tests is real data (not asserted).
- Left as is, for you: the extension import points extensions at their folder **inside Arc's data directory** (no copy), so they stop working if Arc is removed; it also skips only one built-in extension id by name.

### 5. Onboarding / first-run audit
- Checked: no Arc logo or Arc image anywhere in Swift code (only SF Symbols; icons are `Icons/alp_browser_*.icns` set at launch from `alp_selected_icon`, default `alp_browser_original`);
  there is no quit dialog or `NSAlert` and no custom recovery/error screen (nothing to leak); no `arc://` in Swift sources; the unfocused tab close is an `xmark` (the `minus` is only on the *focused* retained tab, as "Unload Tab").
- **Gap fixed:** first launch with an Arc install went straight into imported tabs and never opened `alpbrowser.app/start` (only the no-Arc fallback did). `BrowserState.performArcImport` now puts a Start tab first in the first imported space and makes it active.
  `makeStartTab()` is shared by both paths. No new steps, no redesign.
- Not verified (needs the Mac): that the shipped `.icns` files and the PSDs contain no Arc artwork (run 5 looked at the PNGs; icon/PSD authorship is still your item), and that the Dock shows the Alp icon before `applicationDidFinishLaunching`.
- Out of scope but noticed: `Sources/AlpOCIBridge/AlpOCIBridge.m` still has Arc strings; it is not in the Swift package and you have not decided on it.

## Build risks to check first on the Mac
1. `NoteMarkdownStyler.swift`: private nested `LineKind`/`LineInfo` used in private static signatures; the tuple `open: (index:marker:count:)?`; `text.substring(with:) as NSString`; the nested `absolute`/`isFree` functions capturing `line`/`blocked`; `NSFont.monospacedDigitSystemFont`.
2. `AlpSidebarImporter.swift`: `private final class ImportContext` used by private static functions, `LocalizedError` enum, `(try? ...)?[.size] as? NSNumber`.
3. `BrowserState.swift`: `performArcImport` (`if case ArcImportError.notFound = error` against `Error`, the `var newSpaces` filter closure, mutating `firstRunSpaces[0]`), `resizeFocusedSplitPane`, `dropSidebarTab`.
4. `AlpBrowserApp.swift`: two more menu items with `.keyboardShortcut(.rightArrow/.leftArrow, modifiers: [.control, .option])`.
5. Tests: `AlpSidebarImporterTests` builds JSON with `#"..."#` raw strings and `\#( )` interpolation; the colour assertions in the styler tests rely on `NSColor` equality (see run 7 note). `bundle-app.sh` compiles `Views/*.swift`, so `NoteMarkdownStyler.swift` and the rest are included without changes.
6. Everything in runs 3–7's lists still stands.

## Runtime checks (unverified assumptions)
- ⌃⌥→/← actually reach the menu items when a web view or a note pane has focus (a WKWebView or NSTextView could swallow them); check 2, 3 and 4 panes, both orientations, relaunch keeps sizes.
- Dragging a tab from the sidebar onto a single page starts a split (the drop layer's `hitTest` assumption from run 7 now matters for the most common case), and a cancelled drag leaves clicks/scroll working.
- Typing a closing fence restyles the block between; deleting it restores normal styling; long notes still type smoothly (a line scan per keystroke).
- Manual "Import from Arc": run it twice (second says everything is already here), with Arc data renamed away (message, nothing changes), and with a hand-damaged JSON.

## Still remaining
- Pane-focus shortcuts exist, but there are still no keyboard moves for a pane's position, and no ↑/↓ resize aliases (grow/shrink is the same in both orientations).
- Runtime checks from runs 3–7 (ad-block compile, boosts, double window, CRX flows, hibernation memory numbers, divider drags).
- No persisted peek; hibernated tabs have no placeholder; pop-up restyle correction still needs your description.

## Needs your decision
1. **Manual re-import now merges instead of replacing.** It is the only behaviour that cannot lose the user's own tabs; say if you want an explicit "replace everything" option as well.
2. **First-launch Start tab** is added to the first imported space and made active after an Arc import (the brief says first launch routes to `alpbrowser.app/start`). Say if imported users should land on their tabs instead.
3. **Import limits** (10,000 tabs, 256 MB file, 40 levels) and the **URL allow-list** (`http`, `https`, `file`, `about:`) are my choices.
4. **Shortcut choice** ⌃⌥←/→ for pane resizing and the 3% step.
5. **Extensions imported from Arc stay in Arc's folder** (no copy); decide whether to copy them into the app's own folder.
6. Still yours from earlier runs: Peek "new window", dropped-on pane's old tab, 12% / 20–80% bounds, auto-hibernate default, hibernation placeholder, zip policy, 4-pane cap, CRX2, countersignature, extension permission prompt, `archivedTabs` cap, two Settings UIs, sync crypto, `.handlesExternalEvents`, git history, `AlpOCIBridge.m` / `ALP_REBRANDING_MANIFEST.md`, "Import from Arc" wording, favicon policy, OCI daemon deployment, icon/PSD authorship.
