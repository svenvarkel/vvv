# macOS 15+ release build (arm64)

## Intent

> "aga kas see töötab siis natuke vanemate macOS-de peal ka, eelmisel ja üle-eelmisel versioonil?"
> "räägime ainult M-kiipidega mäkkidest" / "min toetatud versioon võib olla jah see Sequoia ehk 15"
> "intel mäkkidele saab Fulvio vist ise buildida selle. Mina hoolitsen ainult m-chippide eest"

Today the release bundle needs macOS 27: VVV is built with the host's deployment target, Homebrew bottles
(wxWidgets, TagLib, jpeg, png, tiff, webp, lzma, pcre2, zstd) carry minos 26.0 / 27.0.

## Acceptance criteria

1. Every Mach-O in the release VVV.app has minos <= 15.0 (arm64 only).
2. The release app starts and opens a catalog on macOS 27 (this Mac) under the hardened runtime, notarized.
3. The same DMG starts and opens a catalog on macOS 26 (Sven's kid's Mac).
4. The build fails if any Mach-O in the bundle has minos > the minimum, so a regression cannot ship silently.
5. Dev builds against Homebrew (`build/`) keep working unchanged.

## Verification

1. fixup gate (otool LC_BUILD_VERSION minos) — integration, every build
2. local launch with `-s <scratch settings>` + copy of the pristine catalog, then notarized DMG via quarantine — prod smoke
3. Sven on the macOS 26 Mac — prod smoke (manual)
4. the gate in (1); proven once by running it on today's Homebrew bundle, which must fail
5. configure + build `build/` without the deps prefix

## Approach

- `scripts/build-deps-macos.sh` (new): downloads wxWidgets 3.3.3 and TagLib 2.3.2 (+ utfcpp if the tarball lacks it),
  verifies SHA-256, builds **static** libs into `deps/prefix` with `MACOSX_DEPLOYMENT_TARGET=15.0`, arm64.
  wx: `--disable-shared --disable-sys-libs` (builtin jpeg/png/tiff/zlib/expat/regex), `--without-libwebp`,
  `--without-liblzma`, `--disable-plugins`. Skips work when `deps/prefix` already has both.
- `CMakeLists.txt`: default `CMAKE_OSX_DEPLOYMENT_TARGET` 15.0 (cache, like the architectures).
- `src/CMakeLists.txt`: define `TAGLIB_STATIC` on Apple when the found TagLib is a `.a`.
- `vvv-Info.plist`: `LSMinimumSystemVersion` 15.0 (Finder shows a clear message on older systems).
- `MACOSX_fixup_bundle.sh`: gate — minos of every Mach-O <= `LSMinimumSystemVersion` from the bundle's Info.plist.
  Firebird's libs are 12.7 / 15.0, so they pass as they are.
- `scripts/release-macos.sh`: run build-deps, configure with `-DCMAKE_PREFIX_PATH=deps/prefix`
  `-DwxWidgets_CONFIG_EXECUTABLE=deps/prefix/bin/wx-config`.
- README: release section mentions the deps build.

Rollback: revert the branch; Homebrew dev builds are not touched, deps/prefix is gitignored.

## Plan review (Codex, 2026-10-02)

Verified against the repo; adopted:

- The minos gate runs only when `VVV_MIN_MACOS` is set (the release script sets 15.0); the deployment target
  is passed by the release script too. `src/CMakeLists.txt` runs the fixup on every Apple install, so a global
  gate would break the Homebrew dev install (contradicts AC5). AC5 is verified through `cmake --install`.
- The gate compares against that fixed value, not the bundle's plist; a Mach-O without a readable minos or with an
  architecture other than arm64 fails too.
- TagLib is built with `WITH_ZLIB=OFF` (no zlib linkage question); `/opt/homebrew` is ignored while building deps,
  so utfcpp comes from the TagLib tarball and nothing links to Homebrew.
- Pinned URLs + SHA-256 for both tarballs; wx flags checked against the downloaded `configure --help`
  (`--with-macosx-version-min=15.0` added); `wx-config --libs` and the VVV link line inspected after the build.
- `deps/prefix/.stamp` (versions, target, arch) written only after both installs succeed; reuse requires a match.

Accepted as a known gap: macOS 15 itself is not runtime-tested (no 15 machine); only 26 and 27 are.
Rejected: keeping the previous DMG for rollback — it does not launch on macOS 27 and must not ship.
