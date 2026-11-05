# Claude Code run 14 — revert start page, Arc-correct new-tab behavior

Owner correction: Arc has no new-tab page (the clock/beach screenshot was the Momentum extension). Only the new-tab command bar exists.

## Changed
- DELETED `Sources/AlpBrowser/Views/StartPageView.swift` (clock, greeting, goal field, backdrop).
- `Models/AlpModels.swift`: `TabItem.isStartPage` replaced by `isBlank` (web tab whose URL is empty or `about:blank`). The `alpbrowser.app/start` URLs are no longer special-cased.
- `Views/WebViewContainer.swift`: blank tab renders `Color.clear` over the window background; no web view is created, no page drawn.
- `Services/BrowserState.swift`:
  - removed `openStartTab()`;
  - `openNewTab` opens the command bar when it creates a foreground blank web tab;
  - `handleCommandBarInput` fills the active tab in place when it is blank (no empty tab left behind); ⌘T / `openCommandBar` itself is unchanged;
  - first-run Start tab is now `about:blank` titled "New Tab" (was `https://alpbrowser.app/start`), and the command bar is presented on first run (both the Arc-import path and the default-spaces path).
- `AlpBrowserApp.swift`: removed the ⌥⌘T "New Tab Page" menu item.
- `Views/SidebarView.swift`, `Views/MainBrowserWindow.swift`: renamed `isStartPage` to `isBlank` (URL pill and nav pill show "Search or Enter URL…" for blank tabs, as before).

Not touched: run 13 top-bar alignment, `AlpWindowChrome`, `AlpTopBarIconButton`, DMG background/script, non-https warning triangle.

## Verified
- No Swift toolchain on this box, so no `swift build`. Re-read the full diff by eye.
- `grep -rniE "StartPage|isStartPage|openStartTab|New Tab Page|alpbrowser.app/start"` over `Sources/` returns nothing. (`APP_HISTORY_NOTES.md` still mentions alpbrowser.app/start as history; left alone.)

## Needs CI / a real Mac / a human decision
- CI build must confirm it compiles (`Color.clear` in the ZStack switch, `isBlank` call sites).
- Check on a Mac: first launch shows the command bar over an empty pane; picking a URL navigates the blank tab and the web view appears; Esc on the first-run bar leaves a blank "New Tab" row in the sidebar (no auto-cleanup of abandoned blank tabs was added).
- Existing users with a saved `https://alpbrowser.app/start` tab in their store will now load that URL (blank only for the new `about:blank`); decide whether to migrate those.
- Nothing in the app currently creates a blank tab except first run; the "+ New Tab" row and ⌘T still just open the command bar (existing behavior), which then creates the tab on submit.
- Nothing committed or pushed.
