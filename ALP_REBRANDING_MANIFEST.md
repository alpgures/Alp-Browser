# Alp Browser — Complete Graphic Assets & Proprietary Terminology Manifest

This manifest catalogs **every single graphic, screenshot, video, Lottie animation, and icon** inside `Alp Browser.app` (`Contents/Resources/*.bundle`) that contains Arc / The Browser Company visual branding, along with **every single proprietary Arc-exclusive term and copywriting blurb** that should be customized.

> **Hot-Swappable Custom Graphics Folder:**
> `libArcOCIBridge.dylib` hooks `CUINamedImage -image` (`CoreUI.framework`). Any PNG placed in `/Users/alpgures/Documents/antigravity/arc2.0/CustomGraphics/<AssetName>.png` automatically overrides the corresponding compiled asset inside `Assets.car` at runtime without needing to recompile `Assets.car`.

---

## Part 1: Every Graphic, Screenshot, Video & Icon to Remake

### A. Settings & Preferences Screenshots (`ARC_PreferencesFeature.bundle`, `ARCUI_ARCUI.bundle`, `ARC_ProfilesUI.bundle`)
| Asset Name | Bundle Location | Dimensions (`@1x` pt / `@2x` px) | Where It Appears / What It Shows | Current Status |
| :--- | :--- | :--- | :--- | :--- |
| `NewLittleBrowserImage` | `ARC_PreferencesFeature.bundle/.../Assets.car` | `685 × 224 pt` (`1370 × 448 px`) | Top hero banner in **Settings → Links** showing a pink Little Arc window at `arc.net` | **Replaced at runtime** by `AlpCreateMiniWindowBannerCGImage()` showing `🔒 alpbrowser.app/start` (or drop `CustomGraphics/NewLittleBrowserImage.png`) |
| `LittleArcHeroImage` | `ARC_PreferencesFeature.bundle/.../Assets.car` | `684 × 135 pt` (`1368 × 270 px`) | Legacy hero banner in **Settings → Links** | **Replaced at runtime** by `AlpCreateMiniWindowBannerCGImage()` |
| `MaxBanner` | `ARC_PreferencesFeature.bundle/.../Assets.car` | `108 × 48 pt` (`216 × 96 px`) | Header graphic in **Settings → Max** | **Replaced at runtime** by custom native **Alp AI (OCI Claude Code)** Settings pane |
| `TidyTabsPreview` | `ARCUI_ARCUI.bundle/.../Assets.car` | `188 × 119 pt` (`376 × 238 px`) | **Settings → Max** illustration for *Tidy Tabs* (broom icon in sidebar) | **Replaced** by custom native **Alp AI** Settings pane |
| `InstantLinksPreview` | `ARCUI_ARCUI.bundle/.../Assets.car` | `188 × 119 pt` (`376 × 238 px`) | **Settings → Max** illustration for *Instant Links* (`Searching the web...`) | **Replaced** by custom native **Alp AI** Settings pane |
| `HoverCardPreview` | `ARCUI_ARCUI.bundle/.../Assets.car` | `702 × 444 pt` (`1404 × 888 px`) | **Settings → Max** illustration for *5-Second Previews* | **Replaced** by custom native **Alp AI** Settings pane |
| `RenameTabTitlesPreview` | `ARCUI_ARCUI.bundle/.../Assets.car` | `188 × 119 pt` (`376 × 238 px`) | **Settings → Max** illustration for *Tidy Tab Titles* | **Replaced** by custom native **Alp AI** Settings pane |
| `DownloadRenamePreview` | `ARCUI_ARCUI.bundle/.../Assets.car` | `702 × 444 pt` (`1404 × 888 px`) | **Settings → Max** illustration for *Tidy Downloads* (`Navan Itinerary.pdf`) | **Replaced** by custom native **Alp AI** Settings pane |
| `ChatGPTSiteSearchPreview` | `ARCUI_ARCUI.bundle/.../Assets.car` | `702 × 444 pt` (`1404 × 888 px`) | **Settings → Max** green illustration for *ChatGPT in the Command Bar* | **Removed completely** (ChatGPT disabled & replaced by OCI Claude Code) |
| `AskOnPagePreview` | `ARCUI_ARCUI.bundle/.../Assets.car` | `702 × 444 pt` (`1404 × 888 px`) | **Settings → Max** illustration for *Ask on Page* | **Replaced** by custom native **Alp AI** Settings pane |
| `ArcASettings` | `ARCClients_BaseAssets.bundle/.../Assets.car` | `120 × 101 pt` (`240 × 202 px`) | Toolbar icon for **Settings → Icon** tab (shows Arc `A` squiggle logo) | **Replaced at runtime** on `NSToolbarItem` with `app.dashed` SF Symbol |
| `MaxFlower` / `MaxFlowerIcon` / `MaxFlowerCenter` / `MaxFlowerBackground` | `ARCClients_BaseAssets.bundle/.../Assets.car` | `22 × 22 pt` to `26 × 26 pt` | 4-petal flower toolbar icon for **Settings → Max** tab | **Replaced at runtime** on `NSToolbarItem` with `sparkles` SF Symbol (`Alp AI`) |
| `ProfilePicker` / `ProfilePickerText` | `ARC_ProfilesUI.bundle/.../Assets.car` | Vector / Multi-scale | Top illustration in **Settings → Profiles** | Drop `CustomGraphics/ProfilePicker.png` to customize |

### B. Account Trading Card, Referral & Sync Graphics (`ARC_MembershipCard.bundle`, `ARC_ReferralCodeFeature.bundle`, `ARC_SidebarSyncCloudKit.bundle`)
| Asset Name | Bundle Location | Dimensions (`@1x` pt / `@2x` px) | Where It Appears / What It Shows | Current Status |
| :--- | :--- | :--- | :--- | :--- |
| `BrowserCompany` | `ARC_MembershipCard.bundle/.../Assets.car` | `255 × 91 pt` (`510 × 182 px`) | `"BROWSER COMPANY"` wordmark stamp on the bottom-right of the Membership Card | **Blanked to transparent** + entire `Alp` tab replaced by **Alp OCI Cloud Passport** |
| `stamp` | `ARC_MembershipCard.bundle/.../Assets.car` | `396 × 396 pt` (`792 × 792 px`) | `"ARC \| <Date>"` stamp on the bottom-left of the Membership Card | **Blanked to transparent** + entire `Alp` tab replaced |
| `AnimatingCardBlob`, `Shape1`–`Shape4`, `fallback-gradient-1`–`8`, `Lines` | `ARC_MembershipCard.bundle/.../Assets.car` | `208 × 192 pt` to `634 × 669 pt` | Trading card artwork shapes & gradients in **Settings → Alp** | **Replaced** by custom native **Alp OCI Cloud Passport** view |
| `archibald+arcenio`, `giftIcon`, `logoIcon` | `ARC_ReferralCodeFeature.bundle/.../Assets.car` | `190 × 107 pt`, `14 × 14 pt`, `15 × 13 pt` | `"Gift Arc to a Friend"` referral ticket dialog illustrations | **Removed** from **Settings → Alp** tab |
| `arcOutlineIcon` | `ARC_SidebarSyncCloudKit.bundle/.../Assets.car` | `136 × 112 pt` (`272 × 224 px`) | Small Arc logo at the bottom center of the **Recovery Phrase Card** | **Blanked to transparent** at runtime (or drop `CustomGraphics/arcOutlineIcon.png`) |

### C. Sign-In, Onboarding & Welcome Videos/Graphics (`ARC_AuthFeature.bundle`, `ARC_WelcomeToArcFeature.bundle`)
| Asset Name / File | Bundle Location | Dimensions / Format | Where It Appears / What It Shows | Current Status |
| :--- | :--- | :--- | :--- | :--- |
| `static-bg.png` | `ARC_AuthFeature.bundle/Contents/Resources/static-bg.png` | Loose PNG file (`1440 × 1800 px`) | Right-half of the **Sign-In Window** showing purple Arc sidebar with `mfzine.com`, `Bauhaus`, `Met Museum`, and an Easel toolbar | Replace file directly at `ARC_AuthFeature.bundle/Contents/Resources/static-bg.png` |
| `demo.mov` | `ARC_AuthFeature.bundle/Contents/Resources/demo.mov` | Loose QuickTime video | Onboarding animation video inside `ARC_AuthFeature.bundle` | Replace file directly or bypass onboarding |
| `intro-music.mp3` | `ARC_AuthFeature.bundle/Contents/Resources/intro-music.mp3` | Loose MP3 audio | Onboarding music track | Replace or mute |
| `WelcomeLogo` / `LogoWithBackdrop` | `ARC_AuthFeature.bundle/.../Assets.car` | `120 × 101 pt` / `56 × 50 pt` | Arc squiggle logo above `"Sign in — Welcome back to Alp."` | Drop `CustomGraphics/WelcomeLogo.png` & `CustomGraphics/LogoWithBackdrop.png` |
| `ContentIntro1` / `ContentIntro2` | `ARC_AuthFeature.bundle/.../Assets.car` | `301 × 211 pt` / `300 × 376 pt` | Onboarding intro cards | Drop `CustomGraphics/ContentIntro1.png` & `ContentIntro2.png` |
| `new_tab.mp4`, `pinning.mp4`, `space_swiping.mp4`, `split_view.mp4` | `ARC_WelcomeToArcFeature.bundle/Contents/Resources/` | Loose MP4 videos | Welcome tour videos | Replace directly in `ARC_WelcomeToArcFeature.bundle` |

### D. App Icons, Brand Marks, Watermarks & Mascots (`Assets.car`, `ARCClients_BaseAssets.bundle`, `ARC_AskArc.bundle`, `ARC_EaselUI.bundle`)
| Asset Name / File | Bundle Location | Dimensions (`@1x` pt) | Where It Appears / What It Shows | Current Status |
| :--- | :--- | :--- | :--- | :--- |
| `AppIcon.icns` | `Contents/Resources/AppIcon.icns` | macOS `.icns` bundle | Finder & Dock application icon | Replace `Contents/Resources/AppIcon.icns` with custom **Alp Browser** `.icns` |
| `icon-arc` | `Contents/Resources/Assets.car` | `512 × 512 pt` | Internal 512pt app icon | Drop `CustomGraphics/icon-arc.png` |
| `AppIconOriginal`, `AppIconColorful`, `AppIconSchoolbook`, `AppIconNeon`, `AppIconHologram`, `AppIconFlutedGlass`, `AppIconCandy`, `AppIconEarlyBirds`, `AppIconDev`, `AppIconCanary` (+ `*Preview`) | `ARCClients_BaseAssets.bundle/.../Assets.car` | `1024 × 1024 pt` (`64 × 64 pt` previews) | Alternate app icons shown in **Settings → Icon** | Drop `CustomGraphics/AppIconOriginal.png`, etc. |
| `DiaAppIcon*` (`Beta`, `Canary`, `Dev`, `Pro`, `Prototype`) | `ARCClients_BaseAssets.bundle/.../Assets.car` | `1024 × 1024 pt` | Unused Dia browser icons bundled by TBC | Ignore or blank |
| `ArcCaptureWatermark` | `Contents/Resources/Assets.car` | `254 × 32 pt` | `"Captured with Arc"` watermark on screenshots | **Blanked to transparent** at runtime |
| `ArcFavicon`, `ArcResourcesFavicon`, `ArcShortcutsFavicon`, `ArcTemplateIcon`, `WelcomeToArcFavicon`, `NotionArcResourcesFavicon` | `ARCClients_BaseAssets.bundle/.../Assets.car` | `18 × 18 pt` to `124 × 124 pt` | Sidebar favicons for internal pages (`alp://`, shortcuts, etc.) | Drop replacement PNGs in `CustomGraphics/` |
| `AppLogo`, `ArcLogoOutline`, `LoadingArcLogoBlur` | `ARC_AskArc.bundle/.../Assets.car` | `160 × 160 pt`, `19 × 16 pt`, `556 × 508 pt` | Ask on Page (Command+F AI) logo & loading blur | Drop replacement PNGs in `CustomGraphics/` |
| `ArcUpdatesArcLogo` / `ArcUpdatesGradient` | `ARCUI_ARCUI.bundle/.../Assets.car` | `74 × 68 pt` / `498 × 183 pt` | Update banner logo | Sparkle updates disabled; can also drop in `CustomGraphics/` |
| `ArchieDialogIcon`, `archie`, `icon-archie*` | `ARC_AdBlocking.bundle`, `ARC_ProfilesUI.bundle`, `ARC_EaselUI.bundle` | `14 × 14 pt` to `495 × 512 pt` | TBC's "Archie" mascot character icons | Drop replacement PNGs in `CustomGraphics/` |
| `Adena`, `Alexandra`, `Hursh`, `Josh`, `Kristina`, `Molly`, `Nate`, `Samir` | `ARC_EaselUI.bundle/.../Assets.car` | `60 × 60 pt` | TBC employee avatars used in Easel collaboration demos | Drop replacement PNGs in `CustomGraphics/` |
| `ChatGPTIcon` / `OpenAIIconTemplate` | `ARCClients_BaseAssets.bundle`, `ARC_CommandBar.bundle` | `70 × 72 pt` / `320 × 320 pt` | OpenAI / ChatGPT icons | ChatGPT permanently disabled |

---

## Part 2: Every Proprietary Arc Term & Copywriting Blurb to Rebrand

### 1. Core Feature & Product Terminology
| Original Arc Term | Where It Appears | Recommended **Alp Browser** Term | Status |
| :--- | :--- | :--- | :--- |
| **Arc / Arc Browser** | App name, Menu bar, Dialogs, Window titles | **Alp / Alp Browser** | **Done** (Binary + runtime AppKit swizzle) |
| **Arc Max / Max** | Settings toolbar tab, AI features | **Alp AI** (or **Alp Studio**) | **Done** (Renamed toolbar tab & window title to `Alp AI`, custom pane) |
| **Little Arc** | Settings → Links, Menus, Shortcuts (`⌥⌘N`) | **Mini Alp** (or **Quick Alp**) | **Done** (Patched in binary `__TEXT,__cstring` to `Mini Alp`) |
| **Peek** | Settings → Links (`Shift`-click preview) | **Quick Peek** / **Inline Preview** | **Done** (Updated description copy in binary) |
| **Air Traffic Control** | Settings → Links (`Routes let you choose...`) | **Link Routing Rules** | **Done** (Patched in binary `__TEXT,__cstring` to `Link Routing Rules`) |
| **Tidy Tabs** | Settings → Max, Sidebar broom button | **Auto-Cluster Tabs** / **Smart Group** | **Done** in `Alp AI` Settings pane |
| **5-Second Previews** | Settings → Max (`Shift`-hover link summary) | **Shift-Hover Link Briefs** | **Done** in `Alp AI` Settings pane |
| **Instant Links** | Settings → Max (`Shift+Enter` in Command Bar) | **Direct Top-Result Navigation** | **Done** in `Alp AI` Settings pane |
| **Tidy Tab Titles** | Settings → Max (Auto-shorten pinned tab titles) | **Compact Pin Labels** | **Done** in `Alp AI` Settings pane |
| **Tidy Downloads** | Settings → Max (Auto-rename downloaded files) | **Smart File Renamer** | **Done** in `Alp AI` Settings pane |
| **ChatGPT in the Command Bar** | Settings → Max, Command Bar | **Removed completely** (Replaced by **OCI Claude Code**) | **Done** (`gptSiteSearchEnabled = NO` + removed from UI) |
| **Ask on Page** | Command+F AI query bar | **OCI Claude Code Page Assistant** | **Done** (Routed to `oci-box` Claude Code) |
| **Boosts / Arc Boost** | Plus menu, Site Control Center | **Alp Styles** / **Page Mods** (`Alp Style`) | Partially rebranded (`Alp Style`); can rename "Boost" -> "Style" globally |
| **Zap** | Inside Boosts editor (element remover) | **Hide Element** / **Snip** | Candidate for Phase 2 string patch |
| **Easel / Easels** | Library, Sidebar `+` menu, Capture | **Canvas** / **Pinboard** | Candidate for Phase 2 string patch |
| **Today Tabs** | Unpinned tabs section below divider | **Active Tabs** / **Session Tabs** | Candidate for Phase 2 string patch |
| **Spaces** | Workspaces at bottom of sidebar | **Spaces** (or **Workspaces**) | Generic enough to keep, or rename to **Workspaces** |
| **Command Bar** | `⌘T` / `⌘L` floating URL & action bar | **Command Bar** (or **Launcher**) | Industry-standard term |
| **Library** | Bottom-left sidebar drawer (Archive, Downloads, etc.) | **Vault** / **Library** | Industry-standard term |
| **Membership Card / Helpful Rogue** | Settings → Alp tab | **Alp OCI Cloud Passport** | **Done** (Replaced by custom native Account & OCI Vault view) |
| **Gift Arc to a Friend / Share Arc** | Settings → Alp tab, Menu bar | **Removed** (Replaced by **Personal Spaces & Server Archive**) | **Done** |
| **Early Birds** | Settings → Advanced / Release channel | **Nightly / Beta Channel** | Candidate for Phase 2 string patch |

### 2. Verbatim Browser Company Copywriting Blurbs Replaced
1. **Settings → Links (Little Arc blurb)**:
   - *Original*: `"Little Arc is a smaller, simpler Arc window. It’s perfect for quick lookups and reading funny tweets your friends send you."`
   - *Replaced with*: `"Mini Alp is a compact, distraction-free popup window built for quick lookups, fast searches, and opening links from any app."`
2. **Settings → Links (Peek blurb)**:
   - *Original*: `"Peek is a way to preview a link without opening a new tab. It’s perfect for quickly looking at a link from an email, news article, or tweet."`
   - *Replaced with*: `"Quick Peek lets you inspect any link in a floating overlay without leaving your current page or cluttering your active workspace with tabs."`
3. **Settings → Max (AI Partner Data Sharing Disclaimer)**:
   - *Original*: `"Max features require that we send data to our AI partners. Learn more about what we send"`
   - *Replaced with*: `"🔒 ChatGPT & OpenAI integrations are permanently removed. Zero browsing data is ever shared with external AI partners."`
4. **Settings → Alp (Gift to a Friend / Referral Icons)**:
   - *Original*: `"Gift Alp to a Friend — Share Alp to unlock exclusive app icons! Click here or in the Icon tab in settings for details."`
   - *Replaced with*: `"Personal Spaces & Server Archive — All 3 Spaces (Personal, Club, Internships), 19 Storable JSONs, and your Markdown export are archived in ~/.arc2-cloud/alp-server-backup on your OCI box."`
