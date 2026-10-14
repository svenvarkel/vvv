#!/bin/bash

# Makes VVV.app self-contained (called by "cmake --install"):
#  - Firebird 5 runtime in Contents/Resources/firebird gets relocatable install names
#  - Homebrew dylibs (wxWidgets, TagLib and their dependencies) are copied to Contents/Frameworks
#  - everything is signed ad-hoc
#  - fails if any Mach-O in the bundle still references a library outside the bundle or the OS

set -euo pipefail

BUNDLEPATH="$1"
EXECFILE="${BUNDLEPATH}/Contents/MacOS/VVV"
FWPATH="${BUNDLEPATH}/Contents/Frameworks"
FBPATH="${BUNDLEPATH}/Contents/Resources/firebird"
mkdir -p "${FWPATH}"
# alias symlinks left by an older version of this script would keep their references from being canonicalized
find "${FWPATH}" -type l -delete

# --- Firebird: the pkg's libfbclient has the framework path as install name, the rest already uses @rpath
FBCLIENT_OLD=/Library/Frameworks/Firebird.framework/Libraries/libfbclient.dylib
install_name_tool -id @rpath/lib/libfbclient.dylib "${FBPATH}/lib/libfbclient.dylib" 2>/dev/null
install_name_tool -change "${FBCLIENT_OLD}" @rpath/lib/libfbclient.dylib "${EXECFILE}" 2>/dev/null
# @rpath/lib/... and @rpath/plugins/... inside the runtime resolve through this rpath of the executable
if ! otool -l "${EXECFILE}" | grep -q '@executable_path/../Resources/firebird'; then
  install_name_tool -add_rpath @executable_path/../Resources/firebird "${EXECFILE}" 2>/dev/null
fi

macho_files() {
  find "${BUNDLEPATH}" -type f | while read -r f; do
    file -b "$f" | grep -q 'Mach-O' && echo "$f"
  done
}

external_deps() {
  # dependencies that live outside the OS (Homebrew or /usr/local)
  otool -L "$1" | tail -n +2 | awk '{print $1}' | grep -E '^(/opt/homebrew|/usr/local)/' || true
}

# --- copy Homebrew libraries into Contents/Frameworks, repeat until no new library shows up.
# A library is referenced by several names (libwebp.7.dylib -> libwebp.7.2.0.dylib): it is copied once under its
# real name and every reference is rewritten to that name. No alias symlinks: with the hardened runtime, macOS 27
# dyld refuses a library whose install name leaf differs from the requested one.
# ponytail: O(files x deps) otool calls per pass, fine for a bundle of ~40 dylibs
resolve() {  # like realpath, which macOS only has since 13
  local p="$1" t
  while [ -L "$p" ]; do
    t=$(readlink "$p")
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
  done
  echo "$(cd "$(dirname "$p")" && pwd -P)/$(basename "$p")"
}
add_lib() {  # $1 = a library path in the Homebrew prefix; sets CANON to its name in the bundle
  local real
  real=$(resolve "$1"); CANON=$(basename "$real")
  if [ ! -f "${FWPATH}/${CANON}" ]; then
    cp "$real" "${FWPATH}/${CANON}"
    chmod u+w "${FWPATH}/${CANON}"
    install_name_tool -id "@rpath/${CANON}" "${FWPATH}/${CANON}" 2>/dev/null
    changed=1
  fi
}
changed=1
while [ $changed -eq 1 ]; do
  changed=0
  while read -r f; do
    for dep in $(external_deps "$f"); do
      add_lib "$dep"
      install_name_tool -change "$dep" "@rpath/${CANON}" "$f" 2>/dev/null
    done
    # Homebrew libraries that already use @rpath/<name> for their siblings
    for name in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | sed -n 's#^@rpath/##p'); do
      if [ ! -e "${FWPATH}/${name}" ] && [ ! -e "${FBPATH}/${name}" ] && [ -e "/opt/homebrew/lib/${name}" ]; then
        add_lib "/opt/homebrew/lib/${name}"
        [ "${CANON}" = "${name}" ] || install_name_tool -change "@rpath/${name}" "@rpath/${CANON}" "$f" 2>/dev/null
      fi
    done
  done < <(macho_files)
done
# copied libraries find each other through their own @loader_path rpath, the executable through its own
for f in "${FWPATH}"/*.dylib; do
  [ -e "$f" ] || continue
  otool -l "$f" | grep -q '@loader_path' || install_name_tool -add_rpath @loader_path "$f" 2>/dev/null
done
if ! otool -l "${EXECFILE}" | grep -q '@executable_path/../Frameworks '; then
  install_name_tool -add_rpath @executable_path/../Frameworks "${EXECFILE}" 2>/dev/null
fi

# --- drop runpaths that point outside the bundle (Homebrew libraries carry their Cellar lib dir):
# dyld would search them before the bundle for @rpath libraries
while read -r f; do
  for p in $(otool -l "$f" | awk '/LC_RPATH/ {getline; getline; print $2}' | grep -v '^@'); do
    install_name_tool -delete_rpath "$p" "$f" 2>/dev/null
  done
done < <(macho_files)

# --- sign (install_name_tool invalidates signatures): libraries first, then the bundle.
# Ad-hoc by default; VVV_SIGN_IDENTITY="Developer ID Application: ..." adds hardened runtime and a
# timestamp, as notarization requires. No entitlements needed: all code carries the same Team ID.
IDENTITY="${VVV_SIGN_IDENTITY:--}"
SIGN_OPTS=(--force --sign "${IDENTITY}")
[ "${IDENTITY}" = "-" ] || SIGN_OPTS+=(--options runtime --timestamp)
while read -r f; do
  [ "$f" = "${EXECFILE}" ] || codesign "${SIGN_OPTS[@]}" "$f"
done < <(macho_files)
codesign "${SIGN_OPTS[@]}" "${BUNDLEPATH}"

# --- gate: nothing may point outside the bundle, /System or /usr/lib
bad=0
while read -r f; do
  if otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -vE '^(@rpath|@loader_path|@executable_path|/System/|/usr/lib/)'; then
    echo "external reference in $f" >&2
    bad=1
  fi
done < <(macho_files)
# every @rpath/<name> must exist in one of the two rpath folders, with an install name ending in that same leaf
while read -r f; do
  for name in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | sed -n 's#^@rpath/##p'); do
    target=""
    for dir in "${FBPATH}" "${FWPATH}"; do  # the executable's rpath order
      [ -e "${dir}/${name}" ] && { target="${dir}/${name}"; break; }
    done
    if [ -z "$target" ]; then
      echo "unresolved @rpath/${name} in $f" >&2
      bad=1
    elif [ "$(basename "$(otool -D "$target" | tail -1)")" != "$(basename "$name")" ]; then
      echo "@rpath/${name} in $f resolves to a library with install name $(otool -D "$target" | tail -1)" >&2
      bad=1
    fi
  done
done < <(macho_files)
# and no runpath may point outside the bundle
while read -r f; do
  if otool -l "$f" | awk '/LC_RPATH/ {getline; getline; print $2}' | grep -v '^@'; then
    echo "external LC_RPATH in $f" >&2
    bad=1
  fi
done < <(macho_files)
# release builds (VVV_MIN_MACOS=15.0, scripts/release-macos.sh): every Mach-O is VVV_ARCH only (default arm64), needs at most that
# macOS. Dev builds link Homebrew bottles made for the host macOS and skip this.
if [ -n "${VVV_MIN_MACOS:-}" ]; then
  plist_min=$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "${BUNDLEPATH}/Contents/Info.plist" 2>/dev/null || true)
  if [ "${plist_min}" != "${VVV_MIN_MACOS}" ]; then
    echo "Info.plist LSMinimumSystemVersion is '${plist_min}', expected ${VVV_MIN_MACOS}" >&2
    bad=1
  fi
  while read -r f; do
    archs=$(lipo -archs "$f" 2>/dev/null || true)
    [ "$archs" = "${VVV_ARCH:-arm64}" ] || { echo "architectures '${archs}' in $f, expected ${VVV_ARCH:-arm64}" >&2; bad=1; }
    # LC_BUILD_VERSION: "minos 15.0"; older binaries: LC_VERSION_MIN_MACOSX "version 12.7"
    minos=$(otool -l "$f" | awk '/LC_BUILD_VERSION/ {k="minos"} /LC_VERSION_MIN_MACOSX/ {k="version"}
                                 k && $1 == k {print $2; exit}')
    if [ -z "$minos" ]; then
      echo "no minimum macOS version in $f" >&2
      bad=1
    elif [ "$(printf '%s\n%s\n' "$minos" "${VVV_MIN_MACOS}" | sort -V | tail -1)" != "${VVV_MIN_MACOS}" ]; then
      echo "$f needs macOS ${minos}, more than ${VVV_MIN_MACOS}" >&2
      bad=1
    fi
  done < <(macho_files)
fi
[ $bad -eq 0 ] || exit 1
echo "VVV.app is self-contained"
