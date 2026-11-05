# Run 17 Summary

## Item 1 — ⌘Q quit warning
**Important:** web search was not permitted in this run, so I could NOT source Arc's real quit wording, buttons,
second-⌘Q behavior or any "don't ask again" setting. The design below is a best guess, labelled
needs-verification. **Owner decision needed:** send a screenshot/description of Arc's quit warning so it can be matched exactly.

What was built:
- `applicationShouldTerminate` in `AlpAppDelegate` intercepts every quit route (⌘Q, menu Quit, Dock Quit) because
  all go through `NSApp.terminate`. First request: returns `.terminateCancel` and shows the card. While the card is up,
  another ⌘Q/Quit returns `.terminateNow`. Shutdown/restart/log-out Apple events are never blocked.
  Skipped when the setting is off or no visible window exists.
- `QuitConfirmationView`: in-window card with the Alp icon, "Quit Alp Browser?", tab/space count line, Cancel
  (Esc / click outside) and Quit (Return), "Press ⌘Q again to quit". No stock NSAlert, no Arc branding.
- Settings > General: "Warn before quitting" toggle (UserDefaults `alp_warn_before_quitting`, default on).
- Cancel/Esc just clears the flag, so there is no half-quit state; confirmed quit still runs
  `applicationWillTerminate` -> `saveImmediately()` unchanged.

## Item 2 — `docs/ARC_BEHAVIOR_AUDIT.md`
10 entries (quit flow, command bar, sidebar, URL dropdown, Downloads, top bar, peek, split view, hibernation,
Mini Alp). Mostly needs-verification; unknowns are marked "needs owner screenshot/description". Citations to
"Arc help documentation" are from recollection, not re-fetched (stated in the file).

## Files changed (by me this run)
- `Sources/AlpBrowser/AlpBrowserApp.swift` (applicationShouldTerminate)
- `Sources/AlpBrowser/Services/BrowserState.swift` (isQuitConfirmationPresented, warnBeforeQuitting, quitSummary)
- `Sources/AlpBrowser/Views/MainBrowserWindow.swift` (overlay + Esc handling)
- `Sources/AlpBrowser/Views/SettingsView.swift` (toggle)
- NEW `Sources/AlpBrowser/Views/QuitConfirmationView.swift`
- NEW `docs/ARC_BEHAVIOR_AUDIT.md`, NEW `CLAUDE_RUN_17_SUMMARY.md`
Run 15/16 edits in other files were left alone. Nothing committed.

## Not verified (no Swift toolchain here; needs CI / a Mac)
- Compiles: not built. Re-read by eye only. Watch: `AEKeyword`/`enumCodeValue` OSType literal comparison, `withAnimation` in the delegate.
- ⌘Q actually reaches the card and a second ⌘Q confirms (SwiftUI default Quit item should route through terminate).
- Card appearance/animation, and that Dock Quit shows it with the app in the background.
- Whether the Arc logo flash on startup/quit still occurs (couldn't test; source grep found no Arc logo refs).
