# App History Notes — distilled from Alp's Antigravity app threads

Source: the active project thread (42 user messages, Nov 4), distilled Nov 4 ~23:00 EST
for the clean-room rewrite agent. This is the decision record — the code alone
does not capture it.

## Origin story (why the rewrite is needed)
- Started as a private experiment for Alp + John (boyfriend, also loves Arc).
- Alp explicitly asked the agent to look at Arc's package/source files and
  reverse-engineer, then to "use the same exact code but just change the online
  components", and asked whether it could copy everything from Arc's package
  contents. That is exactly why the current tree is tainted and must be
  rewritten clean-room before going public.

## Hard constraints (owner decisions, condensed)
- Privacy: the user's data is theirs only. Import extensions + cookies; install
  new extensions from the Chrome Web Store; chrome://settings must work.
- No OCI in the UI: sync settings in general, never mention OCI anywhere
  user-facing (his infra runs on OCI; users must not see it).
- NO Claude Code on OCI for users: do NOT ship that AI feature at all.
  (This supersedes the README's "Arc Max" line.)
- Do NOT note removed features anywhere in the app UI.
- No Arc logo ANYWHERE in the files: not on startup, not in the quit dialog
  (it flashed the Arc logo on quit even after the rebrand), not on recovery
  screens.
- No arc:// URLs anywhere (the "more settings" URL was still arc://).
- No Arc screenshots inside the app.
- Settings layout: he loves Arc's settings layout but calls it "too much" —
  guaranteed C&D territory. Settings + AI/Max features are the FIRST things to
  differentiate. He asked for two lists: every graphic needing a custom
  replacement, and every proprietary Arc-exclusive term to remake.
- Rebrand everything to Alp: app name "Alp Browser", all strings, all graphics.
  At last state the rebrand was incomplete (recovery text, starting tabs,
  quit dialog, startup logo all still leaked Arc).

## Feature decisions
- Engine: he asked for "Chromium-based in SwiftUI" — implemented with WKWebView
  (macOS-native). Keep WKWebView.
- Spaces: Personal + Leisure, frosted color-wheel themes; a color scheme editor
  BETTER than Arc's; read his Arc config for his preferred color; silent
  auto-sync for his own setup.
- Sidebar: 3-tier; style/personalization settings live INSIDE settings, not as
  two icons on the tab sidebar; do not show the space name at the bottom.
- Tabs: unfocused tab close button must be an X, not a minus (minus-button bug);
  fix the tab hover glitch; smoothness is a recurring complaint.
- Gestures: trackpad multi-touch swipes; two-finger swipe right reveals
  library/downloads.
- Onboarding: first sign-in/launch routes to alpbrowser.app/start (his other
  agent builds the start page); stylized new setup flow.
- App icon settings: default alp_browser_original.icns, light alternate
  alp_browser_white.icns; the user can customize the icon BACKGROUND too;
  Alp + General merged into one "General" tab; color buttons must actually
  preview the theme; buttons must match real macOS button sizes.
- Recipient: also for John.

## Open bugs at last state (re-derive fixes in the clean version)
- Startup shows the original Arc logo; the default logo only appears after
  changing it in icon settings.
- Quit dialog flashes the Arc logo momentarily.
- Changing the app icon requires a double-click.
- Permission prompts for folders + the Arc keychain reappear on every update.
- Overlapping elements in settings; custom icon has three corners still pink.
- Alp menu renders pitch white.
- Color buttons do not preview the theme.
- Buttons oversized vs macOS.
- Crash when clicking settings (two crash reports filed in-thread).
- ArcOCIBridge.m had an in-flight fix (uncommitted change) — re-derive it.

## What NOT to carry over
- Anything from Arc's package contents, screenshots, graphics, or proprietary
  terms.
- "Alp Max"/AI features as Arc clones — rebuild from scratch or drop; never
  ship Arc's Max clones.
- Any mention of OCI or Claude Code on OCI in user-facing UI.

Note: one thread message contained a credential; it was deliberately omitted
from this file.
