#!/bin/bash

# Converts a catalog made by VVV <= 1.5 into the Firebird 5 format, from a source checkout:
#
#   scripts/migrate-catalog.sh old.vvv [new.vvv]     (default new name: old-fb5.vvv)
#
# Same converter as VVV.app's (osx_specific/convert-old-catalog.sh), with the Firebird 5 runtime from
# scripts/fetch-firebird.sh and the old engine cached in deps/fb21.

set -euo pipefail

SRC="${1:?usage: $0 old.vvv [new.vvv]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"   # runs here, so the Firebird 5 tools must be this Mac's architecture
VVV_ARCH="${ARCH}" "${ROOT}/scripts/fetch-firebird.sh" >/dev/null
FB5="${ROOT}/deps/fb5"; [ "${ARCH}" = arm64 ] || FB5="${FB5}-${ARCH}"
VVV_FB5="${FB5}/Resources" VVV_FB21="${ROOT}/deps/fb21" \
  exec "${ROOT}/osx_specific/convert-old-catalog.sh" "${SRC}" "${2:-${SRC%.*}-fb5.vvv}"
