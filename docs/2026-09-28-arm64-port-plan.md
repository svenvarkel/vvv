# VVV Apple Silicon port — plan

## Intent

> "kas ja kuidas me saaks selle asja kompileerima ja tööle apple siliconi peale ehk minu m1 peal?"
> "Hakka pihta ja hakka portima." "Ehitame kohalikult, hiljem annan sulle GH remote ka"
> "teeme alguses tasuta asja valmis" (unsigned/ad-hoc first; Developer ID later)

Fork of VVV 1.5 (GPLv2+, SourceForge SVN, author Fulvio Senore) that builds and runs
natively on arm64 macOS.

## Acceptance criteria

1. `cmake` + `cmake --build` on an M1 with Homebrew deps produces an arm64 `VVV.app`.
2. The `.app` is self-contained: no references to `/opt/homebrew` or `/Library/Frameworks/Firebird.framework`
   (`otool -L` on every Mach-O in the bundle), runs on a Mac without Homebrew/Firebird installed.
3. The app opens an existing catalog migrated to FB5 (ODS 13), browses volumes, and search returns results.
4. The app can create a new catalog (restore from bundled `VVV.fbk`) and catalog a volume (a folder).
5. A documented, scripted path converts an old ODS 11 catalog (`.vvv` from VVV ≤1.5) to ODS 13
   without touching the original file.
6. Opening an un-migrated ODS 11 catalog shows an understandable error pointing to the migration script, not a crash.
7. Git history of upstream SVN (489 commits, author Fulvio Senore) preserved; GPL notices kept; README states fork origin.

## Verification

1. build — local build log, `file` on binary.
2. `otool -L` sweep over every Mach-O in the bundle (the gate) + launch with `DYLD_PRINT_LIBRARIES=1` and check no loaded path is outside the bundle or `/System`/`/usr/lib`. A truly clean Mac is not available.
3. manual smoke on Sven's real catalog (`testdata/ext_drive_catalog.fb5.vvv`, 14 volumes, 3.78M files): screenshot of tree + a search.
4. manual smoke: new catalog, add a folder as volume, search a file from it.
5. run script on a copy of `/Users/sven/Catalogue/ext_drive_catalog.vvv`; compare row counts (volumes/files/paths/virtual_*) between source (old isql via Rosetta) and target (FB5 isql).
6. manual: open the original ODS 11 file in the new app.
7. `git log | wc -l`, `git log --format=%an | sort -u`.

## Findings so far (probe build, already done)

- Only compile error with wx 3.3.3 + TagLib 2.3.2: `TagLib::uint` in `src/audio_metadata.cpp`.
- IBPP on Unix links `isc_*` directly → linking `libfbclient.dylib` (FB 5.0.4 arm64 pkg) works.
- FB5 runtime copied to `Contents/Frameworks/firebird/` (lib, plugins, intl, tzdata, *.conf, firebird.msg),
  `libfbclient` id → `@rpath/lib/libfbclient.dylib`, exe rpath `@executable_path/../Frameworks/firebird`,
  `FIREBIRD` env var pointing at that dir → the app opened the migrated catalog (tree visible).
- Migration: old FB 2.1.7 x86_64 embedded `gbak` from the VVV 1.5 DMG runs under Rosetta
  (needs a `firebird.conf` with absolute `RootDirectory`), `gbak -b -g` → `.fbk`, FB5 `gbak -c` → ODS 13.1, UTF8, no errors.

## Approach

Repo: `git svn clone --stdlayout` → `main` (= svn trunk), `develop` from `main`,
work in worktree `.claude/worktrees/arm64-port` on `feature/arm64-port`.

1. `src/audio_metadata.cpp`: `TagLib::uint` → `unsigned int`.
2. `CMakeLists.txt` / `src/CMakeLists.txt`: min version 3.20; TagLib via `find_library(tag)` (dynamic, drop `TAGLIB_STATIC`);
   on APPLE find `fbclient` under `FIREBIRD_ROOT` (cache var, default `deps/fb5`); set `CMAKE_OSX_ARCHITECTURES` default arm64.
3. `src/vvv.cpp` `OnInit` (`__WXMAC__`): `wxSetEnv("FIREBIRD", <bundle>/Contents/Frameworks/firebird)` unless already set, before any DB access.
4. `scripts/bundle-macos.sh`: copy FB5 runtime into bundle, fix install names, bundle wx/TagLib dylibs
   (`dylibbundler` from brew), copy `VVV.fbk`, `vvv-struct-update.fdb`, help, translations, ad-hoc `codesign`,
   then otool sweep that fails on any `/opt/homebrew` or `/Library/Frameworks` reference. Replaces `MACOSX_fixup_bundle.sh` usage on mac.
5. `vvv-struct-update.fdb` (shipped ODS 11 DB used by `UpgradeDatabase`): convert to ODS 13 with the same backup/restore, commit the new binary.
   `VVV.fbk` stays (FB5 gbak restores old backups) — verify by creating a new catalog.
6. `scripts/fetch-firebird.sh`: download FB 5.0.4 arm64 pkg, `pkgutil --expand-full` into `deps/fb5` (no system install, no sudo).
7. `scripts/migrate-catalog.sh <old.vvv> [new.vvv]`: fetches VVV 1.5 x86 DMG (for FB 2.1 embedded gbak) + FB5, backup → restore, row-count check.
8. ODS mismatch: catch the connect error in the catalog-open path and show a message naming the migration script.
9. README-fork.md: origin, license, build steps, migration.

Rollback: everything is on the feature branch in a worktree; `main` stays byte-identical to SVN trunk.
Old catalogs are never written (migration reads a copy / uses `gbak -b` which only reads).

Out of scope for now: signing/notarization, GitHub Actions, universal binary, Windows/Linux build changes.

## Plan review (Codex, 2026-09-28)

Codex (gpt-5.6-sol), findings verified against the code:

1. **High, accepted.** AC2 is not proven by an otool sweep plus one launch on the dev machine. A clean Mac is not available,
   so AC2 is verified as "no external Mach-O dependency detected": the otool sweep covers every Mach-O incl. `plugins/`,
   and the smoke (AC3/AC4: open, search, create a catalog, catalog a volume) runs with `DYLD_PRINT_LIBRARIES=1`.
   Clean-Mac test: Sven's second Mac or a macOS VM later.
2. **Critical, partly checked.** CLI `gbak -c VVV.fbk` on FB5 → ODS 13.1 with all 7 tables (done before the review).
   Not yet checked: the app path goes through the Services API (`Service::StartRestore`, `firebird_db.cpp:101`)
   and embedded `service_mgr`. This is the first thing to test after the bundle is built (AC4).
3. **Medium, accepted.** Do not add a separate `bundle-macos.sh`. On APPLE, the existing CMake `install()` path plus a
   rewritten `MACOSX_fixup_bundle.sh` do the job (FB5 layout, dylib bundling, codesign, otool gate). Bundle name stays `vvv.app`.
4. **High, accepted in reduced form.** `migrate-catalog.sh` writes to a temp file, validates row counts, then atomic `mv`
   and never overwrites an existing target. The original ODS 11 file is only read. In-place `UpgradeDatabase` only runs when
   `DB_VERSION` < expected; a catalog from 1.5 is already current. Rollback = rerun the migration from the original.
5. **Low, rejected.** History preservation is part of the fork Sven asked for ("kas ma võiks teha forki enda githubi alla").

## Diff review (Codex, 2026-09-28)

- P1 `realpath` needs macOS 13+ → replaced with a `readlink` loop. Fixed.
- P2 ODS 11 message pointed to `scripts/`, which the installed app does not have → links the README section. Fixed.
- Follow-up: gate does not prove `@loader_path`/`@executable_path` targets or the effective rpath chain.
  Covered by the runtime check (`DYLD_PRINT_LIBRARIES=1`, nothing loaded from outside the bundle or OS). Not changed.

## Known issues

Moved to [README.md](../README.md#known-issues).
