#!/bin/bash

# Converts a catalog made by VVV <= 1.5 (Firebird 2.x, ODS 11) into the format of this
# build (Firebird 5, ODS 13):
#
#   convert-old-catalog.sh old.vvv new.vvv [log]
#
# Run by VVV.app from Contents/Resources (the Intel build offers it when it opens an old catalog), and by
# scripts/migrate-catalog.sh. The old engine comes from the VVV 1.5 DMG on SourceForge, downloaded once into
# VVV_FB21 (default ~/Library/Application Support/VVV/fb21); VVV_FB5 is a Firebird 5 folder with bin/gbak and
# bin/isql (default: the "firebird" folder next to this script).
#
# The old engine updates the header of every database it opens, so it only gets a copy
# (an APFS clone: instant, no extra space). The new file is written next to the target,
# row counts are compared, and only then the result is moved into place. The old file is never written.
# The old engine is x86_64 only: on Apple silicon this needs Rosetta.

set -euo pipefail

SRC="${1:?usage: $0 old.vvv new.vvv [log]}"
DST="${2:?usage: $0 old.vvv new.vvv [log]}"
[ -z "${3:-}" ] || exec >>"$3" 2>&1

VVV15_URL="https://sourceforge.net/projects/vvvapp/files/VVV/1.5/VVV-1.5-x86_64.dmg/download"
# SourceForge publishes MD5 d5f11fdd48551b1a1e4cfcc467112e12; SHA-256 taken from that verified file
VVV15_SHA256=94605c4466f1706c1445f6a6e4ea44a2a4f306197f8fe435daac81dd36c92ca6
TABLES="VOLUMES PATHS FILES FILES_AUDIO_METADATA VIRTUAL_PATHS VIRTUAL_FILES SERVICE"
NEWFB="${VVV_FB5:-$(cd "$(dirname "$0")" && pwd)/firebird}"
OLDFB="${VVV_FB21:-${HOME}/Library/Application Support/VVV/fb21}"

[ -f "${SRC}" ] || { echo "not found: ${SRC}" >&2; exit 1; }
[ -e "${DST}" ] && { echo "target exists, refusing to overwrite: ${DST}" >&2; exit 1; }
SRC="$(cd "$(dirname "${SRC}")" && pwd)/$(basename "${SRC}")"
DST="$(cd "$(dirname "${DST}")" && pwd)/$(basename "${DST}")"

[ "$(uname -m)" = x86_64 ] || arch -x86_64 /usr/bin/true 2>/dev/null || {
  echo "Rosetta is required: softwareupdate --install-rosetta --agree-to-license" >&2; exit 1; }

# old Firebird 2.1 embedded runtime, taken from the VVV 1.5 DMG; only a complete copy is moved into place
if [ ! -x "${OLDFB}/bin/gbak" ]; then
  mkdir -p "$(dirname "${OLDFB}")"
  FETCH="$(mktemp -d "${OLDFB}.XXXX")"
  trap 'hdiutil detach -quiet "${FETCH}/mnt" 2>/dev/null || true; rm -rf "${FETCH}"' EXIT
  echo "downloading VVV 1.5 for its Firebird 2.1 engine"
  curl -fsSL -o "${FETCH}/vvv15.dmg" "${VVV15_URL}"
  echo "${VVV15_SHA256}  ${FETCH}/vvv15.dmg" | shasum -a 256 -c - >/dev/null || {
    echo "checksum mismatch: ${VVV15_URL}" >&2; exit 1; }
  mkdir "${FETCH}/mnt"
  hdiutil attach -nobrowse -readonly -mountpoint "${FETCH}/mnt" "${FETCH}/vvv15.dmg" >/dev/null
  cp -R "${FETCH}/mnt/VVV.app/Contents/MacOS/firebird" "${FETCH}/fb21"
  hdiutil detach -quiet "${FETCH}/mnt"
  rm -rf "${OLDFB}"
  mv "${FETCH}/fb21" "${OLDFB}"
  rm -rf "${FETCH}"
  trap - EXIT
fi
# the old engine wants an absolute root in firebird.conf
printf 'RootDirectory = %s\n' "${OLDFB}" > "${OLDFB}/firebird.conf"

export ISC_USER=SYSDBA ISC_PASSWORD=masterkey
old() { FIREBIRD="${OLDFB}" "${OLDFB}/bin/$@"; }
new() { FIREBIRD="${NEWFB}" "${NEWFB}/bin/$@"; }   # VVV.app's own FIREBIRD points here too

counts() {  # $1 = old|new, $2 = database
  for t in ${TABLES}; do
    printf '%s ' "$t"
    echo "select count(*) from ${t};" | "$1" isql -q "$2" | awk 'NF==1 && $1 ~ /^[0-9]+$/ {print $1}'
  done
}

WORK="$(mktemp -d "${DST}.XXXX")"
# the old engine leaves its lock manager daemon behind
trap 'rm -rf "${WORK}"; pkill -f "${OLDFB}/bin/fb_lock_mgr" || true' EXIT

# a clone when source and target share an APFS volume, a full copy otherwise
cp -c "${SRC}" "${WORK}/source.vvv" 2>/dev/null || cp "${SRC}" "${WORK}/source.vvv"
echo "backup (Firebird 2.1): ${SRC}"
old gbak -b -g "${WORK}/source.vvv" "${WORK}/catalog.fbk"
echo "restore (Firebird 5): ${DST}"
new gbak -c -page_size 8192 "${WORK}/catalog.fbk" "${WORK}/catalog.vvv"

counts old "${WORK}/source.vvv" > "${WORK}/old.txt"
counts new "${WORK}/catalog.vvv" > "${WORK}/new.txt"
if ! diff "${WORK}/old.txt" "${WORK}/new.txt"; then
  echo "row counts differ, nothing written" >&2; exit 1
fi
cat "${WORK}/new.txt"

mv -n "${WORK}/catalog.vvv" "${DST}"
[ -f "${WORK}/catalog.vvv" ] && { echo "target appeared meanwhile: ${DST}" >&2; exit 1; }
echo "done: ${DST}"
