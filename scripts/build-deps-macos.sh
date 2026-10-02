#!/bin/bash

# Builds static wxWidgets and TagLib into deps/prefix for the release build (arm64, macOS 15+).
# Homebrew bottles target the macOS they were built on, so a bundle made from them only runs there.
# wx uses its built-in jpeg/png/tiff/zlib/expat/regex: no third-party dylib ends up in VVV.app.
# Dev builds keep using Homebrew; scripts/release-macos.sh calls this and points CMake here.

set -euo pipefail

MIN_MACOS=15.0
ARCH=arm64
WX_VERSION=3.3.3
WX_SHA256=81b09d6dd9f1ed9301f8c55a968a488d0491f264dc2bab19a7e407ac67009482
WX_URL="https://github.com/wxWidgets/wxWidgets/releases/download/v${WX_VERSION}/wxWidgets-${WX_VERSION}.tar.bz2"
TAGLIB_VERSION=2.3.2
TAGLIB_SHA256=3ca2d8afaa7f1cf7f6ed10e511ebc368bfacd6dcaa3dbfa690b89e502e8963dc
TAGLIB_URL="https://taglib.org/releases/taglib-${TAGLIB_VERSION}.tar.gz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/deps/src"
PREFIX="${ROOT}/deps/prefix"
STAMP="wx ${WX_VERSION} taglib ${TAGLIB_VERSION} macos ${MIN_MACOS} ${ARCH}"

if [ "$(cat "${PREFIX}/.stamp" 2>/dev/null)" = "${STAMP}" ]; then
  echo "deps already in ${PREFIX}"
  exit 0
fi
rm -rf "${PREFIX}"
mkdir -p "${SRC}"

fetch() {  # $1 = url, $2 = sha256; prints the local path. Runs in $(...), where set -e does not apply: exit explicitly
  local f="${SRC}/$(basename "$1")"
  [ -f "$f" ] || curl -fL -o "$f" "$1" >&2 || exit 1
  echo "$2  $f" | shasum -a 256 -c - >&2 || { echo "checksum mismatch: $f" >&2; exit 1; }
  echo "$f"
}

export MACOSX_DEPLOYMENT_TARGET="${MIN_MACOS}"
JOBS=$(sysctl -n hw.ncpu)

# --- TagLib
tb="$(mktemp -d)"
trap 'rm -rf "${tb}"' EXIT
taglib_tar=$(fetch "${TAGLIB_URL}" "${TAGLIB_SHA256}")
wx_tar=$(fetch "${WX_URL}" "${WX_SHA256}")
tar xzf "${taglib_tar}" -C "${tb}"
cmake -S "${tb}/taglib-${TAGLIB_VERSION}" -B "${tb}/build" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_MACOS}" -DBUILD_SHARED_LIBS=OFF -DWITH_ZLIB=OFF \
  -DBUILD_BINDINGS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
  -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" >/dev/null   # utfcpp from the tarball, not Homebrew's
cmake --build "${tb}/build" -j "${JOBS}" >/dev/null
cmake --install "${tb}/build" >/dev/null

# --- wxWidgets
tar xjf "${wx_tar}" -C "${tb}"
mkdir "${tb}/wxbuild"
(cd "${tb}/wxbuild" && "${tb}/wxWidgets-${WX_VERSION}/configure" --prefix="${PREFIX}" \
  --with-osx_cocoa --with-macosx-version-min="${MIN_MACOS}" --enable-macosx_arch="${ARCH}" \
  --disable-shared --disable-sys-libs --without-libwebp --without-liblzma --without-libcurl \
  --disable-webview --disable-mediactrl --disable-stc --disable-webrequest --disable-secretstore \
  --disable-tests --without-subdirs > configure.out)
if grep -i 'unrecognized option' "${tb}/wxbuild/configure.out" "${tb}/wxbuild/config.log"; then
  echo "wx configure rejected an option" >&2; exit 1
fi
make -C "${tb}/wxbuild" -j "${JOBS}" >/dev/null
make -C "${tb}/wxbuild" install >/dev/null

echo "${STAMP}" > "${PREFIX}/.stamp"
echo "deps built in ${PREFIX}"
