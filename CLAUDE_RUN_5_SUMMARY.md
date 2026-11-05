# Claude Run 5 Summary

**Nothing was built, compiled or run.** Linux box, no Swift toolchain; the Mac build is toolchain-blocked (manifest
link failure, not a code error). Every Swift change below, including the new tests, is unbuilt and untested.
Nothing was committed or pushed. `AlpOCIBridge.m`, `ALP_REBRANDING_MANIFEST.md`, `/home/ubuntu/arc-reference` and the
OCI daemon were not touched. I did not study the Arc binary. The only binary I looked at is `Alp Browser.app`'s own
executable, and only with `file`.

## What I changed

1. **CRX signature verification**
   - `Services/CRXVerifier.swift` (new): offline parser and verifier for CRX2 and CRX3. Details below.
   - `Services/AlpExtensionManager.swift`: `installFromWebStore` now calls `CRXVerifier.verify(data, expectedExtensionID:)`
     before anything is unzipped or installed. `unpackCRX` (which only stripped the header) became `unzipPayload`, which
     only unzips the already-verified payload. A failure aborts the install and shows the error from
     `CRXVerificationError` in `lastErrorMessage`. The rest of the install flow is unchanged.
   - `Tests/AlpBrowserTests/CRXVerifierTests.swift` (new): builds signed CRX3 (ECDSA and RSA) and CRX2 files in memory
     with fresh keys. Cases: valid files, tampered payload, wrong expected ID, signer that is not the ID key, no proofs,
     bad magic/version, truncated or oversized header, corrupted signature, DER shape checks.

   **What is verified**
   - Magic, version, and header length bounds (header ≤ 1 MiB, no truncation).
   - CRX3: the protobuf header is parsed. Every RSA (PKCS#1 v1.5 + SHA-256) and ECDSA (P-256 + SHA-256) proof is verified
     over `"CRX3 SignedData\0" + LE32(len) + signed_header_data + zip`. One bad proof fails the whole file. At least one proof is required.
   - CRX3: the 16-byte `crx_id` in the signed header must equal the first 16 bytes of SHA-256 of one of the verified
     signing keys. Otherwise the file is refused.
   - CRX2: RSA PKCS#1 v1.5 + SHA-1 over the zip, as the format specifies. RSA keys under 1024 bits are rejected.
   - The extension ID derived from the signing key must equal the ID the user asked for. A package for a different extension is refused.

   **What is NOT verified**
   - That the key belongs to a trusted publisher. The format is self-signed: the check proves that the contents match the
     key that the extension ID is derived from, not who holds that key. Chrome's Web Store countersignature (Google's
     publisher key proof) is not checked. I did not hardcode Google's key because I can't confirm its bytes from here.
     The download over HTTPS from Google plus the ID binding is what protects against swapped or modified packages.
   - CRX2 uses SHA-1, which is weak. The request still says `acceptformat=crx2,crx3`. I left that alone. Dropping `crx2` would
     be stricter, and the Web Store should serve CRX3.
   - Zip contents are not scanned. I did not add a zip-slip check on top of `ditto`.
   - Unpacked extensions from the folder picker and the Arc importer are not signed and are not checked.

2. **Note formatting wraps selections** (`Views/EaselNoteAndLibraryView.swift`)
   - `TextEditor` in `NoteEditorView` is replaced by `NoteTextView`, an `NSViewRepresentable` over
     `NSTextView.scrollableTextView()`.
   - `NoteTextController` (new, `@MainActor`) holds the text view.
     - **B / I / Code** wrap the selection and keep the inner text selected. With no selection they insert `**text**` at the cursor and select the placeholder.
     - **H1 / H2 / List / Quote** add the prefix to every line the selection touches, or remove it if every line already has it.
   - Edits go through `shouldChangeText` / `replaceCharacters` / `didChangeText`, so undo works and the delegate fires.
   - The 350 ms debounce is unchanged: `.onChange(of: draftBody)` is still on the view, `textDidChange` writes the binding, and `commitBody` is as before.
   - The font, 6 pt line spacing, no background and 36 pt side padding match the old editor.

3. **Provenance audit**: no replacements made. File by file:
   - `Icons/alp_browser_original.icns` and `alp_browser_white.icns`: viewed. A black rounded square with a gradient
     mountain glyph, and a white square with a black mountain. These are the owner's app icons and were not touched. The glyph is not Arc's mark.
   - `Icons/alp_mountain_mask.png`: viewed. The white mountain glyph on a rounded-square mask, used by `AlpIconGenerator`. Original-looking. Kept.
   - `Icons/alp_logo_template_mask.png`: viewed. The same silhouette as a red/green colour-keyed template. Nothing in the tree references it.
   - `Icons/alp_browser_dark.psd`, `alp_browser_white.psd`: Photoshop sources (1024², RGBA 16-bit). Embedded metadata says
     Adobe Photoshop 26.5/27.11 and a Display P3 profile. No Arc names or text in the metadata. The XMP create date is 2025-04-05.
     That is much earlier than the repo, so these could have started from a template. The tree cannot show whether or where from. Left alone.
   - `CustomGraphics/`: empty directory (git does not track it). The only reference is the hot-swap lookup in `AlpOCIBridge.m`. Nothing to audit.
   - `Alp Browser.app/`: a gitignored build artifact (`*.app/` in `.gitignore`), not in git. It holds
     - the same icons: `AppIcon.icns` = `alp_browser_original.icns`, and the white icns and mask PNG, all byte-identical to `Icons/` (checked with `cmp`);
     - an `Info.plist` with Alp names, bundle id `com.alpgures.alpbrowser`, no Arc keys, matching the `bundle-app.sh` template;
     - `PkgInfo`, `_CodeSignature/CodeResources`, which only list the four resources above;
     - `MacOS/AlpBrowser`, a 5.9 MB arm64 Mach-O. I only ran `file` on it. Its origin is not provable from the tree. A SwiftPM build of this package is a plausible 5.9 MB, but I did not verify that, and I did not inspect its contents.
   - Not provable from the tree: the original authorship of the glyph and the PSDs. I'd ask the owner to confirm they drew them. Nothing was deleted or replaced.

4. **Compile-risk sweep**: I found **no definite compile errors and changed nothing**. Reviewed:
   - `WebViewPool` ad-block (`lookUpContentRuleList` / `compileContentRuleList` closures, `store?.` on the IUO `default()`, nested `[weak self]`, `AdBlockRules.json()` from a non-isolated closure, the multi-line `boostUserScripts` strings). All valid under Swift 5 mode as far as the language rules show. Sendable captures of `WKContentRuleList` could at most warn.
   - `EaselNoteAndLibraryView` `onMutate` closures. The function-typed parameter inside a function-typed stored property is non-escaping, and passing it on to `mutateElement` is legal. Initialiser argument order and the `BrowserState` members used all exist.
   - `FaviconCache`. `guard let (data, response) = try? await …` is valid Swift. `data.prefix(_)` on `Data` returns `Data`, so the ternary types agree. The `nonisolated static` functions only read Sendable `static let`s (allowed in-module). `Task.detached { try? … }` is `@discardableResult`.
   - `AlpExtensionManager` macOS 15.4 names (`requestedPermissions`, `optionalPermissions`, `requestedPermissionMatchPatterns`, `optionalPermissionMatchPatterns`, `grantedPermissions`, `grantedPermissionMatchPatterns`, `WKWebExtension(resourceBaseURL:)`, `WKWebExtensionContext(for:)`, `controller.load/unload`). They match my recollection of the API. I can't check them against the SDK from here, so they stay **unverified**.
   - `SpaceThemeStudioView`. `Canvas` with `context.fill(_, with: .linearGradient(...))`, the `Picker` with `Bool` tags, `accessibilityAdjustableAction` with `@unknown default`, memberwise inits for the structs with private `let` defaults, and every model member it uses (`colorStops`, `hsb`, `presets`, `renderedGradientColors`, …) exist with matching types.
   - `@testable import AlpBrowser` on the executable target: SwiftPM supports it (5.5+), and the test target depends on it. Only a real build can confirm it. **Unverified.**
   - Still unverified, because they depend on SDK behaviour I can't see: the nested ternary passed to `.font(...)` on the easel card, which may be slow to type-check; the segmented `Picker` showing only text for `Label` rows; whether the `WKContentRuleListStore`/`WKWebExtension` completion handlers are `@MainActor @Sendable` in your SDK (warnings only).

## Build risks to check first on the Mac
1. `CRXVerifier.swift` (new, most likely place for a typo): `SecKeyCreateWithData` with the bare PKCS#1 key, `SecKeyVerifySignature` and the `Unmanaged<CFError>` handling, `P256.Signing.PublicKey(derRepresentation:)`, `isValidSignature(_:for:)` with a `Data` message, and `Character(UnicodeScalar(UInt8))`.
2. `CRXVerifierTests.swift`: `SecKeyCreateRandomKey` (RSA 2048) and `SecKeyCreateSignature` in tests; `try! signer.key.signature(for:)`. The RSA tests generate 2048-bit keys, so they take a moment.
3. `EaselNoteAndLibraryView.swift`: `NoteTextView` / `NoteTextController`. The `@StateObject private var textController = NoteTextController()` initialiser on a `@MainActor` class; the `@MainActor` `Coordinator` conforming to `NSTextViewDelegate`; and `NSTextView.scrollableTextView()`. Run-time: after pressing a format button, the selection and focus should return to the text view. The buttons are SwiftUI buttons and I assumed that they don't steal first responder.
4. `AlpExtensionManager.swift`: `Task.detached` now runs verify and unzip together. `Self.unzipPayload` is `nonisolated private static`.
5. Everything in run 3 and 4's lists that is not mentioned above is unchanged.

## Still remaining
- Run-time checks from runs 3–4 (ad-block compile at launch, boosts applying, double window on external URLs).
- Pop-up restyle correction (needs the owner's own description).
- Optional hardening: check the Web Store countersignature; drop CRX2; scan zip entries for `..` paths.
- Note editor: no live markdown styling, and no keyboard shortcuts (⌘B / ⌘I) yet.

## Needs your decision
1. **Icon and PSD authorship**: please confirm that you made the mountain glyph and the PSDs. I can't prove it from the tree, and the PSD create date is 2025-04-05.
2. **`AlpOCIBridge.m` / `ALP_REBRANDING_MANIFEST.md`** are still in the tree (as instructed). The bridge and manifest are also the only references to `CustomGraphics/`.
3. **Extension consent UX**, **favicon policy**, **git history purge**, **sync crypto**, **`archivedTabs` cap**, **two Settings UIs**, **`.handlesExternalEvents` fix** and **OCI daemon deployment**: unchanged and still yours.
4. Whether to refuse CRX2 outright (it can only be SHA-1 signed).
