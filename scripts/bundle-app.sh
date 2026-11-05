#!/bin/zsh
set -euo pipefail

PROJECT_DIR="/Users/alpgures/Documents/antigravity/arc2.0"
APP_NAME="Arc2"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${PROJECT_DIR}"
echo "Building Arc 2.0 native macOS binary with swiftc..."

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy official Arc.app asset bundles, textures, shaders, fonts, sound effects, and AppIcon if present
ARC_RESOURCES="/Applications/Arc.app/Contents/Resources"
if [[ -d "${ARC_RESOURCES}" ]]; then
    for item in "AppIcon.icns" "ARC_WindowThemeUI.bundle" "ARC_SpaceStyleEditor.bundle" "ARC_SoundEffects.bundle" "ARCClients_FontsManager.bundle"; do
        if [[ -e "${ARC_RESOURCES}/${item}" ]]; then
            cp -R "${ARC_RESOURCES}/${item}" "${RESOURCES_DIR}/"
        fi
    done
fi

SDK_PATH="$(xcrun --show-sdk-path)"
swiftc -O \
    -target arm64-apple-macosx14.0 \
    -sdk "${SDK_PATH}" \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -framework CoreText \
    -framework AVFoundation \
    Sources/ArcBrowser/Models/*.swift \
    Sources/ArcBrowser/Services/*.swift \
    Sources/ArcBrowser/Views/*.swift \
    Sources/ArcBrowser/ArcBrowserApp.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Arc2</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.alpgures.arc2</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Arc 2.0</string>
    <key>CFBundleDisplayName</key>
    <string>Arc 2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "Successfully built and packaged: ${APP_BUNDLE}"
