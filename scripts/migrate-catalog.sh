#!/bin/bash

# Converts a catalog made by VVV <= 1.5 (Firebird 2.x, ODS 11) into the format of this
# build (Firebird 5, ODS 13):
#
#   scripts/migrate-catalog.sh old.vvv [new.vvv]
#
# The old file is only read. The new file is written next to it (default: old-fb5.vvv),
# row counts are compared, and only then the result is moved into place.
# Needs Rosetta: the old Firebird engine (from the VVV 1.5 DMG) is x86_64 only.

set -euo pipefail

VVV15_URL="https://sourceforge.net/projects/vvvapp/files/VVV/1.5/VVV-1.5-x86_64.dmg/download"
VVV15_MD5=d5f11fdd48551b1a1e4cfcc467112e12
TABLES="VOLUMES PATHS FILES FILES_AUDIO_METADATA VIRTUAL_PATHS VIRTUAL_FILES SERVICE"

SRC="${1:?usage: $0 old.vvv [new.vvv]}"
DST="${2:-${SRC%.*}-fb5.vvv}"
[ -f "${SRC}" ] || { echo "not found: ${SRC}" >&2; exit 1; }
[ -e "${DST}" ] && { echo "target exists, refusing to overwrite: ${DST}" >&2; exit 1; }
SRC="$(cd "$(dirname "${SRC}")" && pwd)/$(basename "${SRC}")"
DST="$(cd "$(dirname "${DST}")" && pwd)/$(basename "${DST}")"

arch -x86_64 /usr/bin/true 2>/dev/null || {
  echo "Rosetta is required: softwareupdate --install-rosetta --agree-to-license" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="${ROOT}/deps"
"${ROOT}/scripts/fetch-firebird.sh" >/dev/null
NEWFB="${DEPS}/fb5/Resources"

# old Firebird 2.1 embedded runtime, taken from the VVV 1.5 DMG
OLDFB="${DEPS}/fb21"
if [ ! -x "${OLDFB}/bin/gbak" ]; then
  DMG="${DEPS}/VVV-1.5-x86_64.dmg"
  [ -f "${DMG}" ] || curl -fL -o "${DMG}" "${VVV15_URL}"
  [ "$(md5 -q "${DMG}")" = "${VVV15_MD5}" ] || { echo "checksum mismatch: ${DMG}" >&2; exit 1; }
  MNT="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -mountpoint "${MNT}" "${DMG}" >/dev/null
  cp -R "${MNT}/VVV.app/Contents/MacOS/firebird" "${OLDFB}"
  hdiutil detach "${MNT}" >/dev/null
fi
# the old engine wants an absolute root in firebird.conf
printf 'RootDirectory = %s\n' "${OLDFB}" > "${OLDFB}/firebird.conf"

export ISC_USER=SYSDBA ISC_PASSWORD=masterkey
old() { FIREBIRD="${OLDFB}" "${OLDFB}/bin/$@"; }
new() { FIREBIRD="${NEWFB}" "${NEWFB}/bin/$@"; }

counts() {  # $1 = old|new, $2 = database
  for t in ${TABLES}; do
    printf '%s ' "$t"
    echo "select count(*) from ${t};" | "$1" isql -q "$2" | awk 'NF==1 && $1 ~ /^[0-9]+$/ {print $1}'
  done
}

WORK="$(mktemp -d "${DST}.XXXX")"
# the old engine leaves its lock manager daemon behind
trap 'rm -rf "${WORK}"; pkill -f "${OLDFB}/bin/fb_lock_mgr" || true' EXIT

echo "backup (Firebird 2.1): ${SRC}"
old gbak -b -g "${SRC}" "${WORK}/catalog.fbk"
echo "restore (Firebird 5): ${WORK}/catalog.vvv"
new gbak -c -page_size 8192 "${WORK}/catalog.fbk" "${WORK}/catalog.vvv"

counts old "${SRC}" > "${WORK}/old.txt"
counts new "${WORK}/catalog.vvv" > "${WORK}/new.txt"
if ! diff "${WORK}/old.txt" "${WORK}/new.txt"; then
  echo "row counts differ, nothing written" >&2; exit 1
fi
cat "${WORK}/new.txt"

mv -n "${WORK}/catalog.vvv" "${DST}"
[ -f "${WORK}/catalog.vvv" ] && { echo "target appeared meanwhile: ${DST}" >&2; exit 1; }
echo "done: ${DST}"
