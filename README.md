# VVV (Virtual Volumes View) for Apple Silicon

VVV catalogs the content of removable volumes (external drives, CDs, DVDs) so you can
browse and search them offline. Folders and files can also be arranged in a virtual
file system that holds files from many volumes.

This is a fork of [VVV](https://vvvapp.sourceforge.net) by Fulvio Senore and the VVV team.
It builds and runs natively on arm64 macOS. The full upstream SVN history
(`svn://svn.code.sf.net/p/vvvapp/code`) is kept in this repository.

## What changed from VVV 1.5

- Native arm64 build with wxWidgets 3.3 and TagLib 2 from Homebrew.
- The embedded database moved from Firebird 2.1 (x86_64 only) to **Firebird 5**. The runtime is
  bundled in `VVV.app/Contents/Resources/firebird`.
- `VVV.app` is self-contained: the wxWidgets and TagLib dylibs are copied into the bundle,
  and the bundle is signed ad-hoc.
- Catalogs made by VVV 1.5 and older must be converted once (see below).

## Build

Requirements: macOS on Apple Silicon, Xcode command line tools, Homebrew.

```bash
brew install cmake wxwidgets taglib
scripts/fetch-firebird.sh                  # official Firebird 5 arm64 pkg, extracted to deps/, no install
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/build/install"
cmake --build build -j
cmake --install build                      # assembles and checks build/install/VVV.app
```

`cmake --install` fails if any library in the bundle still points outside the bundle or macOS.

The app is not notarized yet. On first launch, macOS may block it: open
*System Settings → Privacy & Security* and choose *Open Anyway*, or run
`xattr -dr com.apple.quarantine VVV.app`.

## Converting catalogs from VVV 1.5 and older

Old catalogs use the Firebird 2 on-disk format (ODS 11), and Firebird 5 cannot open it.
Convert each catalog once:

```bash
scripts/migrate-catalog.sh ~/Catalogs/drives.vvv            # writes ~/Catalogs/drives-fb5.vvv
scripts/migrate-catalog.sh ~/Catalogs/drives.vvv new.vvv    # or pick the name
```

The script downloads the VVV 1.5 DMG from SourceForge to get its Firebird 2.1 engine,
which runs under Rosetta (`softwareupdate --install-rosetta` if needed). It backs up the
old catalog with that engine, restores the backup with Firebird 5, and compares the row
counts of every table. The old engine only works on a copy (an APFS clone when possible), so the original
file stays byte-identical. The target is never overwritten.

## Known issues

- Search and cataloging a volume have not been tested through the GUI of this build yet.
- The Firebird engine traps SIGTERM: it closes all database connections and leaves the app running,
  so the next action fails with `Transaction::Start ... invalid database handle`. Quit with Cmd-Q
  instead of `kill`.

## Security notes

Reviewed 2026-09-28 (Codex security review, findings verified).

- The app opens no network ports and makes no network connections, unless you configure a remote
  Firebird server in the options. It writes only catalog files, `~/Library/Preferences/VVV Preferences`
  and Firebird lock files in `/tmp/firebird` (mode 0770, owner only).
- Untrusted input reaches C/C++ parsers: audio tags of files on cataloged volumes (TagLib), and catalogs
  (`.vvv`) someone else gives you (Firebird). Treat foreign catalogs and crafted media like any other
  file you open with a native app.
- Search terms and names are escaped before they go into SQL; no injection path was found.
- The Firebird password in the preferences is only obfuscated. It means nothing for local catalogs,
  but do not store a real password there if you connect to a remote Firebird server.
- The bundled libraries (Firebird, wxWidgets, TagLib, image and compression libraries) are frozen at
  build time: rebuild to pick up their security fixes.
- Before giving the app to others: Developer ID signature with hardened runtime, notarization, a real
  bundle identifier (now `com.yourcompany.vvv`) and pinned dependency versions.

## License

Contributors are listed in [CONTRIBUTORS.md](CONTRIBUTORS.md).


GPL v2 or later, see [COPYING](COPYING). Bundled components keep their own licenses:
Firebird (IPL/IDPL, `Contents/Resources/firebird/License.txt`), IBPP (IBPP License,
`src/ibpp/license.txt`), wxWidgets (wxWindows Library Licence), TagLib (LGPL 2.1 / MPL 1.1).
