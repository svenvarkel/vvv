#!/bin/bash

# Makes vvv.app self-contained (called by "cmake --install"):
#  - Firebird 5 runtime in Contents/Resources/firebird gets relocatable install names
#  - Homebrew dylibs (wxWidgets, TagLib and their dependencies) are copied to Contents/Frameworks
#  - everything is signed ad-hoc
#  - fails if any Mach-O in the bundle still references a library outside the bundle or the OS

set -euo pipefail

BUNDLEPATH="$1"
EXECFILE="${BUNDLEPATH}/Contents/MacOS/vvv"
FWPATH="${BUNDLEPATH}/Contents/Frameworks"
FBPATH="${BUNDLEPATH}/Contents/Resources/firebird"
mkdir -p "${FWPATH}"

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
# real name and the other names become symlinks, so dyld loads a single image.
# ponytail: O(files x deps) otool calls per pass, fine for a bundle of ~40 dylibs
resolve() {  # like realpath, which macOS only has since 13
  local p="$1" t
  while [ -L "$p" ]; do
    t=$(readlink "$p")
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
  done
  echo "$(cd "$(dirname "$p")" && pwd -P)/$(basename "$p")"
}
add_lib() {  # $1 = a library path in the Homebrew prefix
  local real canon alias
  real=$(resolve "$1"); canon=$(basename "$real"); alias=$(basename "$1")
  if [ ! -f "${FWPATH}/${canon}" ]; then
    cp "$real" "${FWPATH}/${canon}"
    chmod u+w "${FWPATH}/${canon}"
    install_name_tool -id "@rpath/${canon}" "${FWPATH}/${canon}" 2>/dev/null
    changed=1
  fi
  if [ "$alias" != "$canon" ] && [ ! -e "${FWPATH}/${alias}" ]; then
    ln -s "$canon" "${FWPATH}/${alias}"
    changed=1
  fi
}
changed=1
while [ $changed -eq 1 ]; do
  changed=0
  while read -r f; do
    for dep in $(external_deps "$f"); do
      add_lib "$dep"
      install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f" 2>/dev/null
    done
    # Homebrew libraries that already use @rpath/<name> for their siblings
    for name in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | sed -n 's#^@rpath/##p'); do
      if [ ! -e "${FWPATH}/${name}" ] && [ ! -e "${FBPATH}/${name}" ] && [ -e "/opt/homebrew/lib/${name}" ]; then
        add_lib "/opt/homebrew/lib/${name}"
      fi
    done
  done < <(macho_files)
done
# copied libraries find each other through their own @loader_path rpath, the executable through its own
for f in "${FWPATH}"/*.dylib; do
  [ -e "$f" ] || continue
  otool -l "$f" | grep -q '@loader_path' || install_name_tool -add_rpath @loader_path "$f" 2>/dev/null
done
if ! otool -l "${EXECFILE}" | grep -q '@executable_path/../Frameworks$'; then
  install_name_tool -add_rpath @executable_path/../Frameworks "${EXECFILE}" 2>/dev/null
fi

# --- sign (install_name_tool invalidates signatures): libraries first, then the bundle
while read -r f; do
  [ "$f" = "${EXECFILE}" ] || codesign --force --sign - "$f" 2>/dev/null
done < <(macho_files)
codesign --force --sign - "${BUNDLEPATH}"

# --- gate: nothing may point outside the bundle, /System or /usr/lib
bad=0
while read -r f; do
  if otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -vE '^(@rpath|@loader_path|@executable_path|/System/|/usr/lib/)'; then
    echo "external reference in $f" >&2
    bad=1
  fi
done < <(macho_files)
# every @rpath/<name> must exist in one of the two rpath folders
while read -r f; do
  for name in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | sed -n 's#^@rpath/##p'); do
    if [ ! -e "${FWPATH}/${name}" ] && [ ! -e "${FBPATH}/${name}" ]; then
      echo "unresolved @rpath/${name} in $f" >&2
      bad=1
    fi
  done
done < <(macho_files)
[ $bad -eq 0 ] || exit 1
echo "vvv.app is self-contained"
