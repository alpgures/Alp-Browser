#!/bin/zsh
#
# package-dmg.sh — Builds a premium, distributable macOS .dmg for Alp Browser.
# Copyright © 2026 Alp Gures. All rights reserved.
#
# Uses create-dmg (https://github.com/create-dmg/create-dmg) for a styled
# installer window: branded background, fixed icon layout, Applications
# drop link. Install it with: brew install create-dmg
# (CI installs it in .github/workflows/swift.yml.)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="Alp Browser"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
DIST_DIR="${PROJECT_DIR}/dist"
DMG_PATH="${DIST_DIR}/Alp-Browser-macOS-arm64.dmg"
STAGING_DIR="${PROJECT_DIR}/build/dmg-staging"
BACKGROUND="${SCRIPT_DIR}/dmg-background.png"

cd "${PROJECT_DIR}"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "App bundle not found. Building first with ./scripts/bundle-app.sh..."
    "${SCRIPT_DIR}/bundle-app.sh"
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "create-dmg not found. Install it with: brew install create-dmg" >&2
    exit 1
fi

echo "Staging files for DMG..."
mkdir -p "${DIST_DIR}"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating styled DMG at ${DMG_PATH}..."
create-dmg \
    --volname "${APP_NAME}" \
    --background "${BACKGROUND}" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "${APP_NAME}.app" 150 180 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 510 180 \
    "${DMG_PATH}" \
    "${STAGING_DIR}"

rm -rf "${STAGING_DIR}"
echo "Successfully created: ${DMG_PATH}"
