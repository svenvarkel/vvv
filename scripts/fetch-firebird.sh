#!/bin/bash

# Downloads the official Firebird 5 macOS package and extracts it (no system install, no sudo):
# arm64 (default) into deps/fb5, VVV_ARCH=x86_64 into deps/fb5-x86_64. CMake picks it up from <dir>/Resources.

set -euo pipefail

FB_VERSION=5.0.4.1812-0
case "${VVV_ARCH:-arm64}" in
  arm64)  FB_ARCH=arm64; FB_SHA256=0c3495ec457720f3b3b51e1be0f36485f589732d6af38c9b04f1eb171d8d5509; FB_DIR=fb5 ;;
  x86_64) FB_ARCH=x64;   FB_SHA256=f6b587d8d16f528b9ce94bf006e204cc171620fbb64b90730790e7af612c2325; FB_DIR=fb5-x86_64 ;;
  *) echo "VVV_ARCH must be arm64 or x86_64" >&2; exit 1 ;;
esac
FB_URL="https://github.com/FirebirdSQL/firebird/releases/download/v5.0.4/Firebird-${FB_VERSION}-macos-${FB_ARCH}.pkg"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="${ROOT}/deps"
PKG="${DEPS}/Firebird-${FB_VERSION}-macos-${FB_ARCH}.pkg"

mkdir -p "${DEPS}"
if [ -d "${DEPS}/${FB_DIR}/Resources/lib" ]; then
  echo "Firebird already in ${DEPS}/${FB_DIR}"
  exit 0
fi

[ -f "${PKG}" ] || curl -fL -o "${PKG}" "${FB_URL}"
echo "${FB_SHA256}  ${PKG}" | shasum -a 256 -c -

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
pkgutil --expand-full "${PKG}" "${TMP}/x"
mv "${TMP}/x/Firebird.pkg/Payload/Versions/A" "${DEPS}/${FB_DIR}"
echo "Firebird ${FB_VERSION} extracted to ${DEPS}/${FB_DIR}"
