#!/bin/zsh
set -euo pipefail

PROJECT_DIR="/Users/alpgures/Documents/antigravity/arc2.0"
APP_NAME="Alp Browser"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${PROJECT_DIR}"
echo "Building Alp Browser native clean-room macOS binary with swiftc..."

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy clean Alp Browser HIG application icons
cp "${PROJECT_DIR}/Icons/alp_browser_original.icns" "${RESOURCES_DIR}/AppIcon.icns"
cp "${PROJECT_DIR}/Icons/alp_browser_original.icns" "${RESOURCES_DIR}/alp_browser_original.icns"
cp "${PROJECT_DIR}/Icons/alp_browser_white.icns" "${RESOURCES_DIR}/alp_browser_white.icns"
cp "${PROJECT_DIR}/Icons/alp_mountain_mask.png" "${RESOURCES_DIR}/alp_mountain_mask.png"

SDK_PATH="$(xcrun --show-sdk-path)"
swiftc -O \
    -target arm64-apple-macosx14.0 \
    -sdk "${SDK_PATH}" \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -framework CryptoKit \
    Sources/AlpBrowser/Models/*.swift \
    Sources/AlpBrowser/Services/*.swift \
    Sources/AlpBrowser/Views/*.swift \
    Sources/AlpBrowser/AlpBrowserApp.swift \
    -o "${MACOS_DIR}/AlpBrowser"

chmod +x "${MACOS_DIR}/AlpBrowser"

cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AlpBrowser</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.alpgures.alpbrowser</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Alp Browser</string>
    <key>CFBundleDisplayName</key>
    <string>Alp Browser</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>HTTP URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>http</string>
                <string>https</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Clean any quarantine and provenance extended attributes
xattr -cr "${APP_BUNDLE}"

# Ad-hoc sign with entitlements
codesign --force --deep --sign - --entitlements "${PROJECT_DIR}/scripts/entitlements.plist" "${APP_BUNDLE}"

# Clear quarantine again after signing
xattr -cr "${APP_BUNDLE}"

# Register bundle with macOS LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${APP_BUNDLE}"

echo "Successfully built and packaged clean-room: ${APP_BUNDLE}"
