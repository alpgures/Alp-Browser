# Claude Code run 19 summary — top-bar insets and sidebar minimum width

No commits, nothing pushed, nothing built (no Swift toolchain; CI verifies). Details and sourcing: `docs/ARC_BEHAVIOR_AUDIT.md` §10–11.

## Arc values measured (from the reference app's binary; numbers only, no code copied)
- Sidebar width: **min 164, max 500, narrow threshold 212, collapse threshold 82**. Default not found (kept 296).
- Top controls: `TopMargin` 4, `topControlsLeadingMargin` 8, `topControlsTrailingMargin` −6, `topControlsToCommandBarSpacing` 2,
  `WindowControlsLeadingPadding` 5, `ToolbarIconSize` 16, button height 32. What each constant means visually is inferred, not traced.

## Changes
1. **Top bar** (`MainBrowserWindow.swift` `AlpTopBarMetrics`, `SidebarView.swift`, `AlpBrowserApp.swift`): centre line 14 → 20 pt
   (4 pt margin + 32 pt row / 2), so the icons are 7 pt below the top edge instead of 1. Traffic lights moved to x = 12 pt
   (idempotent shift) and the first control sits 8 pt after them (`trafficLightInset` 74). URL pill position unchanged (42 pt).
2. **Sidebar minimum**: clamp 260 → 164 via new `AlpSidebarMetrics`; library floor 330 kept (handle's lower limit becomes 330 while the
   Library is open, drag starts from the on-screen width).
3. **Clipping at narrow widths** (`SidebarView.swift`), below 212 pt: nav buttons fold into a "…" menu; Settings moves into the "+" menu;
   space switcher scrolls when it can't fit; media mini-player domain `lineLimit(1)`.

## Deviations from Arc
Icon frame 26 pt (Arc 32); pill stays at 42 pt; cluster trailing inset unchanged; no collapse-on-drag below 82.

## Unverified / risks
Compiles (`Menu` label styling, `ViewThatFits` + `ScrollView`, negative bottom padding); traffic-light x/y on the real titlebar (AppKit may
re-lay out outside the hooked events); narrow-mode look at 164 pt; whether the 12 pt close-button x matches Arc.

## Owner decisions
Collapse the sidebar on drag below 82 like Arc? Make icons the full 32 pt? Trailing inset of the nav cluster (Arc's −6 unresolved)?
