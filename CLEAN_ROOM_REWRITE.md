# Clean-Room Rewrite — Alp Browser

## Why
The current tree derives from Arc.app's code with modifications. That was fine as a
private experiment for Alp + John, but this project is going into Alp's public
portfolio (github.com/alpgures/Alp-Browser). Before anything is pushed, every
source file must be rewritten clean-room: original code, same functionality and
appearance. This removes the copyright exposure (a cease & desist vector).

## Goal
A from-scratch Swift/SwiftUI macOS browser (macOS 14+, same Package.swift layout)
with **identical functionality and appearance** to the current build. Visual
differentiation comes LATER — do not restyle now.

## Hard rules
1. **No code copied from Arc.app** — not from its binary, resources, or any
   decompiled/disassembled form. Every Swift file is written fresh.
2. **No Arc proprietary assets.** `CustomGraphics/` and `Icons/` must be original
   work or replaced. If an asset's origin is Arc, redraw/recreate it.
3. **No Arc trademarks in user-visible strings, no arc:// URLs, no Arc logo
   anywhere (startup, quit dialog, recovery screens), no Arc screenshots** — app name, menus, About panel,
   window titles. Branding is "Alp Browser" (see ALP_REBRANDING_MANIFEST.md).
4. **The Arc sidebar importer stays, rewritten.** Reading the user's OWN
   `~/Library/Application Support/Arc/StorableSidebar.json` to import THEIR data
   is interoperability, not copying — but the parser (`ArcSidebarImporter.swift`)
   must be original code. Same for `ArcAssetLoader.swift` (no Arc assets).
5. **Rename Arc* symbols.** `ArcBrowser` → `AlpBrowser`, `ArcModels`,
   `ArcSidebarImporter`, `ArcOCIBridge`, etc. Update Package.swift targets.
   Keep the Python sync daemon (`Server/alp_cloud_daemon.py`) working —
   update the ObjC bridge it talks to, or rewrite the bridge in Swift.

## Feature parity checklist (all must survive the rewrite)
- WKWebView tabs, lazy loading with snapshot-based 0 MB hibernation
- 1-click import from Arc.app (spaces: Personal, Leisure; favorites preserved)
- Frosted color-wheel space themes, 3-tier sidebar
- WKContentRuleList ad blocking
- Command Bar (Cmd+T), Split View, Peek, Little Arc
- Boosts 2.0, Easels & Notes
- NO Claude Code on OCI / AI feature for users (removed per owner decision);
  generic sync settings only, never mention OCI in user-facing UI
- Zero-knowledge encrypted sidebar vault sync via the OCI daemon (port 8788)

## MIT license eligibility (owner requirement)
- The repo is already set to MIT on GitHub (LICENSE + README exist on the
  remote `main`). The local tree has no LICENSE file — good.
- MIT only works if Alp owns the copyright. The derived tree can NEVER be
  MIT-licensed: putting an MIT header on Arc-derived code misrepresents
  ownership and does not cure the infringement.
- Rule: the rewrite must be thorough ("go heavy") — every file rewritten,
  not a find-replace rebrand. No Arc code path, asset, string, or screenshot
  may survive into the pushed tree. Only then is the tree 100% Alp's and
  MIT-licenseable.
- First push: pull the remote's LICENSE + README into the clean tree, then
  push `main`. No third-party dependencies were found in Package.swift, so
  there is no license-compatibility audit needed unless deps are added later
  (any future dep must be MIT/BSD/Apache-compatible, with attribution kept).

## Git workflow
- Remote `origin` → `github.com/alpgures/Alp-Browser` (private) is already set.
- **Do NOT push the current derived tree.** Not even to the private repo's history
  if the repo will ever go public — tainted history is still tainted.
- First push = the rewritten baseline. Commit the rewrite in logical chunks
  (models → services → views → bridge → daemon glue), then push `main`.
- The in-progress bug fix in `Sources/ArcOCIBridge/ArcOCIBridge.m` is superseded
  by the rewrite — re-derive it in the clean implementation if still applicable.

## Performance bar (non-negotiable)
- "Snappiness" is a rewrite requirement, not a nice-to-have. The current
  build's smoothness complaints ("not smooth enough", tab hover glitch,
  oversized buttons) must NOT regress — the clean version matches or beats
  the current build on launch time, tab switching, and sidebar animation
  smoothness. A slower clean-room version is a failed rewrite.

## Out of scope for this pass
- Visual restyle / brand differentiation (later) — EXCEPT settings layout +
  AI features, which are the FIRST differentiation targets (owner: the current
  settings are too identical and guaranteed C&D territory; produce the custom
  graphics list + proprietary terms list requested in APP_HISTORY_NOTES.md)
- Windows version (parked)
- App Store / notarization packaging
