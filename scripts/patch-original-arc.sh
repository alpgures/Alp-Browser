#!/bin/zsh
set -euo pipefail

PROJECT_DIR="/Users/alpgures/Documents/antigravity/arc2.0"
ORIG_ARC="/Applications/Arc.app"
ALP_APP="${PROJECT_DIR}/Alp Browser.app"
DYLIB_PATH="${ALP_APP}/Contents/MacOS/libArcOCIBridge.dylib"
ARC_BIN="${ALP_APP}/Contents/MacOS/Arc"

if [[ ! -d "${ORIG_ARC}" ]]; then
    echo "Error: ${ORIG_ARC} not found."
    exit 1
fi

echo "1. Cloning ${ORIG_ARC} -> ${ALP_APP} using APFS zero-copy (cp -cR)..."
rm -rf "${ALP_APP}" "${PROJECT_DIR}/Arc-OCI.app" "${PROJECT_DIR}/Arc2.app"
cp -cR "${ORIG_ARC}" "${ALP_APP}"

echo "2. Extracting arm64 slice of executable..."
lipo "${ARC_BIN}" -thin arm64 -output "${ARC_BIN}.arm64"
mv "${ARC_BIN}.arm64" "${ARC_BIN}"
chmod +x "${ARC_BIN}"

echo "3. Compiling libArcOCIBridge.dylib..."
clang -dynamiclib \
    -arch arm64 \
    -O2 \
    -fobjc-arc \
    -framework Foundation \
    -framework AppKit \
    -framework Security \
    -install_name "@executable_path/libArcOCIBridge.dylib" \
    "${PROJECT_DIR}/Sources/ArcOCIBridge/ArcOCIBridge.m" \
    -o "${DYLIB_PATH}"

echo "4. Injecting LC_LOAD_DYLIB and patching UI strings ('Arc' -> 'Alp') in Mach-O binary & MainMenu.nib..."
python3 - "${ARC_BIN}" "${ALP_APP}/Contents/Resources/Base.lproj/MainMenu.nib" << 'PYEOF'
import os
import re
import struct
import sys

bin_path = sys.argv[1]
nib_path = sys.argv[2]
dylib_name = b"@executable_path/libArcOCIBridge.dylib\x00"

with open(bin_path, "r+b") as f:
    data = bytearray(f.read())

    # Parse Mach-O header and locate __TEXT,__cstring section for comprehensive UI rebranding
    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack("<IIIIIIII", data[:32])
    assert magic == 0xFEEDFACF, f"Unexpected Mach-O magic: {hex(magic)}"

    off = 32
    cstring_offset = None
    cstring_size = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", data[off:off+8])
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = data[off+8:off+24].rstrip(b"\x00")
            nsects = struct.unpack("<I", data[off+64:off+68])[0]
            sect_off = off + 72
            for _ in range(nsects):
                sectname = data[sect_off:sect_off+16].rstrip(b"\x00")
                if segname == b"__TEXT" and sectname == b"__cstring":
                    cstring_size, cstring_offset = struct.unpack("<QI", data[sect_off+40:sect_off+52])
                sect_off += 80
        off += cmdsize

    # 1a. Rebrand all human-readable UI strings & strip all TBC/Arc/Dia external links in __TEXT,__cstring
    rebranded_count = 0
    url_scrubbed_count = 0
    if cstring_offset and cstring_size:
        cstr_slice = bytes(data[cstring_offset:cstring_offset+cstring_size])
        parts = cstr_slice.split(b"\x00")
        new_parts = []
        for s in parts:
            orig_s = s
            sl = s.lower()
            # Scrub external TBC / Arc / Dia URLs to point to alpbrowser.app/start
            if (
                (s.startswith(b"https://") or s.startswith(b"http://") or s.startswith(b"mailto:"))
                and not b"diabrowser.engineering" in sl
                and any(dom in sl for dom in [
                    b"arc.net",
                    b"thebrowser.company",
                    b"browsercompany",
                    b"arcinternet",
                    b"diabrowser.com",
                ])
            ):
                L = len(s)
                base = b"https://alpbrowser.app/start"
                if s.startswith(b"mailto:"):
                    rep = b"mailto:hi@alpbrowser.app"
                    if len(rep) <= L:
                        s = rep + (b" " * (L - len(rep)))
                elif L >= len(base):
                    if L == len(base):
                        s = base
                    else:
                        s = base + b"?" + (b"x" * (L - len(base) - 1))
                elif L >= 15:
                    short_base = b"https://alp.app"
                    if L == len(short_base):
                        s = short_base
                    else:
                        s = short_base + b"/" + (b"x" * (L - len(short_base) - 1))
                if len(s) == len(orig_s) and s != orig_s:
                    url_scrubbed_count += 1

            # Rebrand human-readable UI strings
            if (
                b" " in s
                and not s.startswith(b"/")
                and b"Application Support" not in s
                and b"NIBArchive" not in s
                and b"AppleScript" not in s
            ):
                ns = s
                ns = ns.replace(b"The Browser Company", b"Alp Browser Studio ")
                ns = ns.replace(b"ARC RECOVERY PHRASE", b"ALP RECOVERY PHRASE")
                ns = ns.replace(b"Arc Max", b"Alp    ")
                ns = ns.replace(b"Alp Max", b"Alp    ")
                ns = re.sub(rb"\bArc\b", b"Alp", ns)
                ns = re.sub(rb"\bARC\b", b"ALP", ns)
                if len(ns) == len(s) and ns != s:
                    s = ns
                    rebranded_count += 1
            elif s in (b"RESOURCES.ARC.NET", b"resources.arc.net"):
                s = b"ALPBROWSER.APP   " if s.isupper() else b"alpbrowser.app   "
                rebranded_count += 1

            assert len(s) == len(orig_s)
            new_parts.append(s)
        new_cstr_slice = b"\x00".join(new_parts)
        assert len(new_cstr_slice) == cstring_size
        data[cstring_offset:cstring_offset+cstring_size] = new_cstr_slice

    # 1b. Exact equal-byte-length UI & URL replacements
    replacements = [
        (b"ARC RECOVERY PHRASE", b"ALP RECOVERY PHRASE"),
        (b"RESOURCES.ARC.NET", b"ALPBROWSER.APP   "),
        (b"Welcome back to Arc.", b"Welcome back to Alp."),
        (b"Welcome to Arc", b"Welcome to Alp"),
        (b"Arc Browser", b"Alp Browser"),
        (b"About Arc", b"About Alp"),
        (b"Share Arc", b"Share Alp"),
        (b"Hide Arc", b"Hide Alp"),
        (b"Quit Arc", b"Quit Alp"),
        (b"Arc Max", b"Alp    "),
        (b"Ask Arc", b"Ask Alp"),
        (
            b"Little Alp is a smaller, simpler Alp window. It\xe2\x80\x99s perfect for quick lookups and reading funny tweets your friends send you.",
            b"Mini Alp is a compact, distraction-free popup window built for quick lookups, fast searches, and opening links from any app. ",
        ),
        (
            b"Peek is a way to preview a link without opening a new tab. It\xe2\x80\x99s perfect for quickly looking at a link from an email, news article, or tweet.",
            b"Quick Peek lets you inspect any link in a floating overlay without leaving your current page or cluttering your active workspace with tabs.   ",
        ),
        (b"Open Little Alp when I press ", b"Open Mini Alp when I press   "),
        (
            b"Open Little Alp when clicking on links with \xe2\x8c\xa5\xe2\x8c\x98 held",
            b"Open Mini Alp when clicking on links with \xe2\x8c\xa5\xe2\x8c\x98 held  ",
        ),
        (b"Links from other apps open in Little Alp", b"Links from other apps open in Mini Alp  "),
        (b"Archive Little Arcs after:", b"Archive Mini Alps after:  "),
        (b"Archive Little Alps after:", b"Archive Mini Alps after:  "),
        (b"Air Traffic Control\xe2\x80\xa6", b"Link Routing Rules\xe2\x80\xa6 "),
        (b"Air Traffic Control", b"Link Routing Rules "),
        (b"Little Arc", b"Mini Alp  "),
        (b"Little Alp", b"Mini Alp  "),
        (b"Arc is no longer\naccepting new signups", b"Alp Browser is ready\nfor you to sign in"),
        (b"https://arc.net/welcome-to-arc", b"https://alpbrowser.app/start?w"),
        (b"https://arc.net/get-started-with-arc", b"https://alpbrowser.app/start?welcome"),
        (b"https://www.diabrowser.com/getting-started", b"https://alpbrowser.app/start?from=alp-init"),
        (b"arc://settings/searchEngines", b"alp://settings/searchEngines"),
        (b"arc://settings/help", b"alp://settings/help"),
        (b"arc://settings/", b"alp://settings/"),
        (b"arc://settings", b"alp://settings"),
        (b"Button Label; Clicking opens arc://settings.", b"Button Label; Clicking opens alp://settings."),
        (b"arc://history", b"alp://history"),
        (b"arc://extensions", b"alp://extensions"),
        (b"arc://password-manager", b"alp://password-manager"),
    ]
    for old_bytes, new_bytes in replacements:
        if len(old_bytes) == len(new_bytes):
            data = data.replace(old_bytes, new_bytes)

    f.seek(0)
    f.write(data)

    # 2. Inject LC_LOAD_DYLIB into Mach-O header
    LC_LOAD_DYLIB = 0xC
    base_len = 24 + len(dylib_name)
    cmdsize = (base_len + 7) & ~7
    pad_len = cmdsize - base_len
    cmd_bytes = struct.pack("<IIIIII", LC_LOAD_DYLIB, cmdsize, 24, 2, 0x00010000, 0x00010000) + dylib_name + (b"\x00" * pad_len)

    f.seek(32)
    existing_cmds = f.read(sizeofcmds)
    if b"libArcOCIBridge.dylib" not in existing_cmds:
        insert_offset = 32 + sizeofcmds
        f.seek(insert_offset)
        f.write(cmd_bytes)
        f.seek(0)
        new_header = struct.pack("<IIIIIIII", magic, cputype, cpusubtype, filetype, ncmds + 1, sizeofcmds + cmdsize, flags, reserved)
        f.write(new_header)
        print(f"Successfully injected LC_LOAD_DYLIB ({cmdsize} bytes), rebranded {rebranded_count} C-strings, and scrubbed {url_scrubbed_count} TBC/Arc URLs.")

# Patch MainMenu.nib if it exists as a file or keyedobjects.nib inside directory
target_nibs = []
if os.path.isfile(nib_path):
    target_nibs.append(nib_path)
elif os.path.isdir(nib_path):
    for root, _, files in os.walk(nib_path):
        for fn in files:
            if fn.endswith(".nib"):
                target_nibs.append(os.path.join(root, fn))

for nf in target_nibs:
    with open(nf, "r+b") as f:
        nd = f.read()
        nd = re.sub(rb"\bArc\b", b"Alp", nd)
        f.seek(0)
        f.write(nd)
PYEOF

echo "5. Rebranding Info.plist to Alp Browser and disabling Sparkle auto-updates..."
plutil -replace CFBundleName -string "Alp" "${ALP_APP}/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "Alp Browser" "${ALP_APP}/Contents/Info.plist"
plutil -replace SUAutomaticallyUpdate -bool NO "${ALP_APP}/Contents/Info.plist"
plutil -replace SUEnableAutomaticChecks -bool NO "${ALP_APP}/Contents/Info.plist"
plutil -replace SUFeedURL -string "https://localhost/updates.xml" "${ALP_APP}/Contents/Info.plist"

python3 - << 'PYPLIST'
import plistlib, sys
plist_path = "/Users/alpgures/Documents/antigravity/arc2.0/Alp Browser.app/Contents/Info.plist"
with open(plist_path, "rb") as f:
    pl = plistlib.load(f)
uts = pl.get("CFBundleURLTypes", [])
uts.append({
    "CFBundleTypeRole": "Viewer",
    "CFBundleURLName": "Alp Protocol",
    "CFBundleURLSchemes": ["alp", "alpBrowser"]
})
pl["CFBundleURLTypes"] = uts
with open(plist_path, "wb") as f:
    plistlib.dump(pl, f)
PYPLIST

echo "5b. Installing Alp icon assets into package resources..."
cp "${PROJECT_DIR}/Icons/alp_browser_original.icns" "${ALP_APP}/Contents/Resources/alp_browser_original.icns"
cp "${PROJECT_DIR}/Icons/alp_browser_white.icns" "${ALP_APP}/Contents/Resources/alp_browser_white.icns"
cp "${PROJECT_DIR}/Icons/alp_mountain_mask.png" "${ALP_APP}/Contents/Resources/alp_mountain_mask.png"
cp "${PROJECT_DIR}/Icons/alp_browser_original.icns" "${ALP_APP}/Contents/Resources/AppIcon.icns"

# Permanently remove DockTilePlugIn so macOS Dock never loads Arc's original tile on launch/quit
/usr/libexec/PlistBuddy -c "Delete :NSDockTilePlugIn" "${ALP_APP}/Contents/Info.plist" 2>/dev/null || true
rm -rf "${ALP_APP}/Contents/PlugIns/DockTilePlugIn.plugin"

# Replace alert helper icons and eliminate Arc icon from quit/alert confirmation dialogs
for HELPER in "Browser Helper (Alerts).app" "Browser Helper (Aperitif Alerts).app"; do
    HPATH="${ALP_APP}/Contents/Frameworks/ArcCore.framework/Versions/A/Helpers/${HELPER}"
    if [ -d "${HPATH}" ]; then
        cp "${PROJECT_DIR}/Icons/alp_browser_original.icns" "${HPATH}/Contents/Resources/app.icns" 2>/dev/null || true
        cp "${PROJECT_DIR}/Icons/alp_browser_original.icns" "${HPATH}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
        rm -f "${HPATH}/Contents/Resources/Assets.car" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "${HPATH}/Contents/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Alp" "${HPATH}/Contents/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleName Alp Helper (Alerts)" "${HPATH}/Contents/Info.plist" 2>/dev/null || true
    fi
done

# Replace product logo 32px
sips -z 32 32 "${PROJECT_DIR}/Icons/alp_mountain_mask.png" --out "${ALP_APP}/Contents/Frameworks/ArcCore.framework/Versions/A/Resources/product_logo_32.png" 2>/dev/null || true

echo "6. Re-signing ${ALP_APP} and helper bundles..."
xattr -cr "${ALP_APP}"
codesign --force --deep --sign - "${ALP_APP}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${ALP_APP}"

# Also create APFS zero-copy aliases at Arc-OCI.app and Arc2.app so all paths open Alp Browser
cp -cR "${ALP_APP}" "${PROJECT_DIR}/Arc-OCI.app"
cp -cR "${ALP_APP}" "${PROJECT_DIR}/Arc2.app"

echo "Successfully built and signed: ${ALP_APP}"
