#!/usr/bin/env bash
#
# package-dmg.sh — Builds a clean, distributable macOS .dmg for Alp Browser.
# Copyright © 2026 Alp Gures. All rights reserved.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${PROJECT_DIR}/Alp Browser.app"
DMG_NAME="Alp-Browser-macOS-arm64.dmg"
DMG_PATH="${PROJECT_DIR}/dist/${DMG_NAME}"
STAGING_DIR="${PROJECT_DIR}/build/dmg-staging"

# 1. Ensure app bundle is built and signed
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "Building Alp Browser.app first..."
    "${SCRIPT_DIR}/bundle-app.sh"
fi

mkdir -p "${PROJECT_DIR}/dist"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

echo "Staging files for DMG..."
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/Alp Browser.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating compressed DMG at ${DMG_PATH}..."
hdiutil create \
    -volname "Alp Browser" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${STAGING_DIR}"

echo "Successfully created: ${DMG_PATH}"
