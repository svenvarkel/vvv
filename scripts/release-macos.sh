#!/bin/bash

# Builds VVV.app from scratch and packs it into a signed, notarized DMG for distribution.
#
#   VVV_SIGN_IDENTITY="Developer ID Application: <company> (<TEAMID>)" \
#   VVV_NOTARY_PROFILE=vvv-notary scripts/release-macos.sh
#
# One-time setup of the notary profile (the app-specific password stays in the keychain):
#   xcrun notarytool store-credentials vvv-notary --apple-id <apple id> --team-id <TEAMID>
#
# Without VVV_SIGN_IDENTITY it makes an ad-hoc signed DMG and skips notarization,
# which is only useful to test the script.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${ROOT}/build-release"
IDENTITY="${VVV_SIGN_IDENTITY:--}"
if [ "${IDENTITY}" != "-" ]; then
  : "${VVV_NOTARY_PROFILE:?set VVV_NOTARY_PROFILE, see the header of this script}"
  security find-identity -v -p codesigning | grep -qF "${IDENTITY}" || {
    echo "signing identity not in the keychain: ${IDENTITY}" >&2; exit 1; }
fi

"${ROOT}/scripts/fetch-firebird.sh" >/dev/null
rm -rf "${BUILD}"
cmake -S "${ROOT}" -B "${BUILD}" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${BUILD}/install" >/dev/null
cmake --build "${BUILD}" -j
VVV_SIGN_IDENTITY="${IDENTITY}" cmake --install "${BUILD}" | tail -1   # MACOSX_fixup_bundle.sh signs

APP="${BUILD}/install/VVV.app"
codesign --verify --deep --strict "${APP}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "${APP}/Contents/Info.plist")
DMG="${BUILD}/VVV-${VERSION}-arm64.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
ditto "${APP}" "${STAGE}/VVV.app"
ln -s /Applications "${STAGE}/Applications"
hdiutil create -quiet -volname "VVV ${VERSION}" -srcfolder "${STAGE}" -format UDZO -ov "${DMG}"

if [ "${IDENTITY}" != "-" ]; then
  codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"
  # notarytool exits 0 for a rejected submission too, so check the status it prints
  OUT=$(xcrun notarytool submit "${DMG}" --keychain-profile "${VVV_NOTARY_PROFILE}" --wait 2>&1) || true
  echo "${OUT}"
  if ! echo "${OUT}" | grep -q 'status: Accepted'; then
    ID=$(echo "${OUT}" | awk '/^ *id:/ {print $2; exit}')
    [ -n "${ID}" ] && xcrun notarytool log "${ID}" --keychain-profile "${VVV_NOTARY_PROFILE}"
    echo "notarization failed" >&2; exit 1
  fi
  xcrun stapler staple "${DMG}"
  spctl --assess --type open --context context:primary-signature --verbose "${DMG}"
else
  echo "ad-hoc build: not notarized, macOS will warn on other Macs"
fi

shasum -a 256 "${DMG}"
