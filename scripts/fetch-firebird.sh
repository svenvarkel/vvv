#!/bin/bash

# Downloads the official Firebird 5 arm64 macOS package and extracts it into deps/fb5
# (no system install, no sudo). CMake picks it up from deps/fb5/Resources.

set -euo pipefail

FB_VERSION=5.0.4.1812-0
FB_SHA256=0c3495ec457720f3b3b51e1be0f36485f589732d6af38c9b04f1eb171d8d5509
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/v5.0.4/Firebird-${FB_VERSION}-macos-arm64.pkg"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="${DEPS_DIR:-${ROOT}/deps}"
PKG="${DEPS}/Firebird-${FB_VERSION}-macos-arm64.pkg"

mkdir -p "${DEPS}"
if [ -d "${DEPS}/fb5/Resources/lib" ]; then
  echo "Firebird already in ${DEPS}/fb5"
  exit 0
fi

[ -f "${PKG}" ] || curl -fL -o "${PKG}" "${FB_URL}"
echo "${FB_SHA256}  ${PKG}" | shasum -a 256 -c -

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
pkgutil --expand-full "${PKG}" "${TMP}/x"
mv "${TMP}/x/Firebird.pkg/Payload/Versions/A" "${DEPS}/fb5"
echo "Firebird ${FB_VERSION} extracted to ${DEPS}/fb5"
