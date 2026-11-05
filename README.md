# Arc 2.0 — Native SwiftUI & AppKit Browser for macOS

A featherweight, native macOS browser built in **SwiftUI + AppKit** designed to look, feel, and function like **Arc Browser**, with automatic **Zero-RAM Tab Hibernation**, **1-Click Import from Installed `Arc.app`**, and **Self-Hosted Cloud Sync + Arc Max (Claude Code)** on your **OCI Box (`oci-box`)**.

## Key Features

- **1-Click Import from Installed `Arc.app`** (`~/Library/Application Support/Arc/StorableSidebar.json`):
  - Automatically imports your Spaces (`Personal` 🧌 with `#6CBAD9` Light Frosted Sky at 28.8% intensity & 65% grain, and `Leisure` 👹 with `#53465E` Dark Plum at 100% intensity & 95% grain), Top Favorites, Pinned Tabs, and nested Folders.
- **Interactive 2D Frosted Color Wheel (`SpaceThemePickerView`)**:
  - Drag 1, 2, or 3 color dots across Arc's frosted 2D Hue/Saturation dial, adjust Tint Intensity (`intensityFactor`), Analog Grain (`noiseFactor`), Brightness, Light/Dark Frosted appearance, or enter exact Hex codes.
- **Silent Background OCI Cloud Sync**:
  - Automatically and silently syncs every change in the background to `oci-box:~/.arc2-cloud/arc2_store.json` without any popups or notifications.
- **Authentic 3-Tier Arc Sidebar**:
  - Top URL Command Pill with quick Copy Link (`⌘⇧C`), Split View (`⌃⇧=`), and Boost Studio (`⚡`) actions.
  - Top Favorites Grid across Spaces.
  - Pinned Tabs & Recursive Collapsible Folders per Space (with automatic "Return to Pinned URL" indicator when a pinned tab navigates away).
  - Divider with `Clear` button + `+ New Tab` row + Unpinned `Today` Tabs (with 12-hour Auto-Archive).
  - Collapsible Sidebar (`⌘S`) with left-edge hover auto-peek floating sidebar.
- **Featherweight Memory Architecture (`0 MB` Sleeping Tabs)**:
  - Lazy `WKWebView` instantiation: your 200+ imported Pinned Tabs use **0 MB of WebContent RAM** until clicked.
  - Automatic background tab hibernation (captures a Retina snapshot and terminates the underlying WebContent process after idle timeout or via 1-click **Hibernate Background Tabs**).
  - Native WebKit bytecode Content Rule List ad & tracker blocker (`WKContentRuleListStore`).
- **Signature Arc Workflows**:
  - **Command Bar (`⌘T` / `⌘L`)**: Instant tab switching, URL/search navigation, and built-in Arc commands.
  - **Split View (`⌃⇧=` / `⌃⇧-`)**: Side-by-side horizontal or vertical multi-pane browsing.
  - **Arc Peek (`Shift + Click` any link)**: Preview external links in a floating modal sheet over your current tab.
  - **Little Arc (`⌘⌥N`)**: Standalone floating quick-lookup window with 1-click expansion into any Space.
  - **Arc Boosts 2.0 (`⌘⇧B`)**: Per-domain color wheel adjustments, smart dark invert, custom CSS/JS, and interactive **Element Zapper** (click any page element to permanently hide it).
  - **Arc Easels (`⌘⇧E`) & Notes (`⌘⇧N`)**: Built-in infinite-style visual boards and notes right inside your tabs.
  - **Arc Max (`⌘F`)**: Combined Find-on-Page + **Ask on Page / 5-Second Summary** powered by Claude Code on your OCI box (`oci-box`).
  - **Self-Hosted OCI Cloud Sync**: Backs up and restores Spaces, Pinned Tabs, Folders, Boosts, Easels, and Notes to `oci-box:~/.arc2-cloud/arc2_store.json`.

## Building & Running

```bash
./scripts/bundle-app.sh
open Arc2.app
```
