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
  bundled in `vvv.app/Contents/Resources/firebird`.
- `vvv.app` is self-contained: the wxWidgets and TagLib dylibs are copied into the bundle,
  and the bundle is signed ad-hoc.
- Catalogs made by VVV 1.5 and older must be converted once (see below).

## Build

Requirements: macOS on Apple Silicon, Xcode command line tools, Homebrew.

```bash
brew install cmake wxwidgets taglib
scripts/fetch-firebird.sh                  # official Firebird 5 arm64 pkg, extracted to deps/, no install
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/build/install"
cmake --build build -j
cmake --install build                      # assembles and checks build/install/vvv.app
```

`cmake --install` fails if any library in the bundle still points outside the bundle or macOS.

The app is not notarized yet. On first launch, macOS may block it: open
*System Settings → Privacy & Security* and choose *Open Anyway*, or run
`xattr -dr com.apple.quarantine vvv.app`.

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

## License

GPL v2 or later, see [COPYING](COPYING). Bundled components keep their own licenses:
Firebird (IPL/IDPL, `Contents/Resources/firebird/License.txt`), IBPP (IBPP License,
`src/ibpp/license.txt`), wxWidgets (wxWindows Library Licence), TagLib (LGPL 2.1 / MPL 1.1).
