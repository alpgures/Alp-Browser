#!/bin/zsh
#
# package-dmg.sh — Builds a clean, distributable macOS .dmg for Alp Browser.
# Copyright © 2026 Alp Gures. All rights reserved.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="Alp Browser"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
DIST_DIR="${PROJECT_DIR}/dist"
DMG_PATH="${DIST_DIR}/Alp-Browser-macOS-arm64.dmg"
STAGING_DIR="${PROJECT_DIR}/build/dmg-staging"

cd "${PROJECT_DIR}"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "App bundle not found. Building first with ./scripts/bundle-app.sh..."
    "${SCRIPT_DIR}/bundle-app.sh"
fi

echo "Staging files for DMG..."
mkdir -p "${DIST_DIR}"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating compressed DMG at ${DMG_PATH}..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"
echo "Successfully created: ${DMG_PATH}"
