# Alp Browser

Light, snappy, and vertical — make browsers user-first again.

A featherweight, native macOS browser built from the ground up in **SwiftUI + AppKit** for macOS 14+, designed with authentic vertical sidebar workflows, automatic **Zero-RAM Tab Hibernation**, **1-Click Sidebar Importer**, and end-to-end self-hosted encrypted sync.

## Key Features

- **Vertical 3-Tier Sidebar**:
  - Smooth hover navigation pill with quick action menu.
  - Pinned Favorites 2×2 grid across spaces.
  - Pinned Tabs & Collapsible Folders per Space with automatic URL retention.
  - Subtle divider with unpinned Today tabs + inline `+ New Tab` trigger.
  - Collapsible Sidebar (`⌘S`) with auto-peek gesture support.
- **Space Themes**:
  - Smooth frosted linear gradients with custom space tinting, light/dark appearance, and space switching animations.
- **Featherweight Memory Architecture**:
  - Lazy `WKWebView` instantiation: sleeping tabs consume 0 MB WebContent RAM.
  - Automatic snapshot hibernation and native WebKit content blocking.
- **Signature Workflows**:
  - **Command Bar (`⌘T` / `⌘L`)**: Instant tab switching and URL search navigation.
  - **Split View (`⌃⇧=` / `⌃⇧-`)**: Side-by-side multi-pane browsing.
  - **Quick Peek (`Shift + Click`)**: Link preview sheets over your current tab.
  - **Mini Alp (`⌘⌥N`)**: Standalone floating quick-lookup window.
  - **Canvas & Notes**: Visual scratchboards and markdown notes right inside your spaces.
  - **Self-Hosted Vault Sync**: Client-encrypted state synchronization.

## Building & Running

```bash
# Build the native macOS application bundle
./scripts/bundle-app.sh
open "Alp Browser.app"

# Or package a distributable compressed macOS .dmg installer (2.8 MB)
./scripts/package-dmg.sh
# Generates dist/Alp-Browser-macOS-arm64.dmg
```
