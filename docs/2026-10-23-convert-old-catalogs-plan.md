# VVV converts old catalogs by itself (Intel Macs)

## Intent

Sven, 2026-10-23: "kuidas vanade intel macide peal saaks teha nii, et userid saaks seal konvertida. See on ka
upgrade path: 1) kasuta uusimat vvv.app intel mac peal ja konverdi oma kataloog ära 2) kopeeri kataloog Apple
Silicon mäki peale." And: "1) kui on vana, siis downloadib taustal selle vvv, võtab sealt vajaliku komponendi ja
konverdib kataloogi (teeb koopia) 2) seejärel avab uues formaadis kataloogi". The old catalog MUST stay intact.
Apple Silicon / Rosetta is explicitly out of scope ("eraldi keiss").

## Acceptance criteria

1. Intel build (x86_64): opening a VVV <= 1.5 catalog (Firebird 2, ODS 11, `isc_wrong_ods`) asks whether to convert
   it into a new copy. No → same as today (error message with the how-to link).
2. Yes → the user picks the new file name (default `<old>-fb5.vvv` next to the old one); the app downloads the
   VVV 1.5 DMG from SourceForge once, verifies its SHA-256, keeps only its Firebird 2.1 folder in
   `~/Library/Application Support/VVV/fb21`, backs up a clone of the catalog with the old gbak, restores it with
   the bundled Firebird 5, and opens the new catalog (which then gets the usual DB_VERSION upgrade).
3. The old catalog file is never opened by either engine and its bytes and mtime are unchanged.
4. Any failure (no network, checksum, gbak error, restore error) shows the error, leaves no half-written new
   catalog, and leaves the old one untouched. A second attempt reuses the cached Firebird 2.1.
5. arm64 build: unchanged behaviour (message with link).
6. Release DMG still notarizes (nothing old inside the bundle).

## Verification

1, 2, 4 (app flow): arm64 dev build with the feature forced on, a catalog whose header ODS is patched to 11
   (FB5 then raises isc_wrong_ods), and a fake `fb21/bin/gbak` in the cache dir (copies a prebuilt FB5 .fbk), so
   download is skipped. Failure: fake gbak exiting 1, and a target in a read-only folder. — integration
2 (download/extract/checksum): run the script's fetch part on this Mac with an empty cache dir. — integration
2, 3 (real old engine): Sven on his Intel Mac (Monterey) with a real VVV 1.5 catalog; shasum + stat of the old
   file before/after. — prod smoke
5: arm64 build shows the old message. 6: notarized x86_64 release DMG.

## Approach

- `osx_specific/convert-old-catalog.sh SRC FBK CACHE`: fetch + verify + extract Firebird 2.1 into CACHE (once),
  write its firebird.conf (absolute RootDirectory), APFS-clone SRC into a temp dir, `gbak -b -g` the clone into FBK,
  kill the old `fb_lock_mgr`, delete the clone. Sets FIREBIRD itself (the app's env points at the bundled FB5).
  Installed into Contents/Resources (macOS only).
- `scripts/migrate-catalog.sh` (dev tool) keeps working; it calls the new script for fetch+backup instead of its
  own copy of that code, and keeps its FB5 gbak restore + row-count comparison.
- `mainframe.cpp`, outside DialogBlocks sections, `#if defined(__WXOSX__) && defined(__x86_64__)`:
  in the `ecWrongODS` case, ask; on yes `ConvertOldCatalog(fileName)`: save dialog for the target (must not exist,
  must be creatable — same checks as RestoreDatabase), wxBusyInfo, `wxExecute` the script synchronously with
  captured stderr, then `CBaseDB::CreateFirebirdDatabaseOnDisk` (FB5 service restore) into the target, remove the
  temp .fbk, on any error delete the target and show stderr / the exception. Then `OpenDatabase(newFile, ...)`.
- No FB5 gbak in the bundle: the embedded FB5 service API already restores (used for new catalogs from VVV.fbk).
- No row-count comparison in the app: gbak and the service restore fail loudly on errors. (ponytail; add when a
  silent loss shows up.)
- Rollback: revert the merge; nothing persistent besides the cache dir, which is safe to delete.

## Plan review (Codex, 2026-10-23)

Real, and how the approach changes (Intent and criteria above stay as written):

- AC3 contradicts the trigger: FB5 attaches to the original first and fails with `isc_wrong_ods`. AC3 is
  verified as "bytes and mtime unchanged", which is what Sven asked for ("old catalog intact").
- No second implementation in C++. `scripts/migrate-catalog.sh` becomes `osx_specific/convert-old-catalog.sh`
  (SRC DST [LOG]), installed in Contents/Resources and run by the app; the dev script stays as a thin wrapper.
  That keeps its staging dir beside DST + `mv -n` publication (no overwrite, cleanup only of owned files), the
  APFS-clone-or-copy fallback, and the old/new row-count comparison. So FB5 `gbak` + `isql` go into the bundle
  (Resources/firebird/bin, rpath @loader_path/.., ~3.8 MB); the IBPP service restore is not used.
- Firebird 2.1 cache: download and extract into a temp dir, then move into place; a partial cache is never
  published.
- Conversion only for local catalogs (not `connectToServer`); server catalogs keep today's message.
- Pre-Unicode catalogs (DB version < 14): after conversion the existing Unicode-conversion dialog follows, as it
  does today for FB2 catalogs. Not changed.
- Release gate: Sven converts a real VVV 1.5 catalog with the installed notarized x86_64 DMG, empty cache, on
  Monterey. Here: arm64 build with a fake old gbak for the app flow, script fetch/extract with an empty cache.
- Rejected: proving the IBPP service restore (no longer used).
