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
ARCH="${VVV_ARCH:-arm64}"   # x86_64 for Intel Macs: a separate DMG, cross-compiled on Apple silicon
BUILD="${ROOT}/build-release-${ARCH}"
IDENTITY="${VVV_SIGN_IDENTITY:--}"
if [ "${IDENTITY}" != "-" ]; then
  : "${VVV_NOTARY_PROFILE:?set VVV_NOTARY_PROFILE, see the header of this script}"
  security find-identity -v -p codesigning | grep -qF "${IDENTITY}" || {
    echo "signing identity not in the keychain: ${IDENTITY}" >&2; exit 1; }
  # the profile lives in the data-protection (iCloud / Local Items) keychain, unreadable while the screen is
  # locked: notarytool then reports "No Keychain password item found". Check before a 10-minute build.
  xcrun notarytool history --keychain-profile "${VVV_NOTARY_PROFILE}" >/dev/null || {
    echo "notary profile ${VVV_NOTARY_PROFILE} unreadable: keep the Mac unlocked, or run store-credentials" >&2; exit 1; }
fi

MIN_MACOS=15.0   # keep in sync with scripts/build-deps-macos.sh and LSMinimumSystemVersion in vvv-Info.plist
DEPS="${ROOT}/deps/prefix"; FB="${ROOT}/deps/fb5"
[ "${ARCH}" = arm64 ] || { DEPS="${DEPS}-${ARCH}"; FB="${FB}-${ARCH}"; }
export VVV_ARCH="${ARCH}"
"${ROOT}/scripts/fetch-firebird.sh" >/dev/null
"${ROOT}/scripts/build-deps-macos.sh"   # static wxWidgets + TagLib for macOS 15, not the Homebrew bottles
rm -rf "${BUILD}"
cmake -S "${ROOT}" -B "${BUILD}" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${BUILD}/install" \
  -DCMAKE_OSX_ARCHITECTURES="${ARCH}" -DFIREBIRD_ROOT="${FB}/Resources" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" -DwxWidgets_CONFIG_EXECUTABLE="${DEPS}/bin/wx-config" \
  -DCMAKE_PREFIX_PATH="${DEPS}" -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" >/dev/null
cmake --build "${BUILD}" -j
# MACOSX_fixup_bundle.sh signs, and fails on any binary that is not ARCH (VVV_ARCH) or needs more than MIN_MACOS
VVV_SIGN_IDENTITY="${IDENTITY}" VVV_MIN_MACOS="${MIN_MACOS}" cmake --install "${BUILD}" | tail -1

APP="${BUILD}/install/VVV.app"
codesign --verify --deep --strict "${APP}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "${APP}/Contents/Info.plist")
DMG="${BUILD}/VVV-${VERSION}-${ARCH}.dmg"

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
