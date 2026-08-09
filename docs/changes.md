# Changes

## Unreleased

### Experimental static-Haskell native linking

`buildNativeLib` now accepts `nativeLinkMode = "static-haskell"` on Linux.
This mode preserves GHC boot-package `.dyn_o` files in a custom native GHC
output, builds PIC archives from them, installs package-level `.dyn_o` archives
for the root/local Haskell packages, and links the final public shared library
manually with the C compiler.

The resulting native artifact has no `DT_NEEDED` entries for `libHS*.so`.
Non-system C dependencies required by the RTS and numeric/runtime support, for
example `libgmp` and `libffi`, are still dynamic libraries, but they are copied
into the native bundle. The custom native GHC used by this mode disables RTS
DWARF unwind and NUMA support, which removes the `libdw`, `libelf`, `libnuma`,
and compression-library dependency chain from typical bundles. Glibc/system
libraries remain external.

This mode is opt-in because the first build requires a native GHC rebuild.
The default `nativeLinkMode = "dynamic"` path is unchanged.

Measured on a small Linux reference bundle, static-Haskell mode with copied
non-system C dependencies first produced `11` `.so` files. Building the custom
RTS without DWARF unwind and NUMA support reduced the bundle to `3` files: the
public FFI library, `libffi`, and `libgmp`.

### Runtime shared-library bundles prune unused Template Haskell dependencies

Android and native bundle builders now prune unused direct `DT_NEEDED` entries
from the root Haskell FFI shared library before recursively copying runtime
dependencies. This keeps dependencies that resolve at least one currently
undefined dynamic symbol and removes dependencies that do not. Missing
candidates and platform system libraries are left untouched.

The pruning step removes build-time Template Haskell libraries from runtime
bundles when they are only retained by Cabal/GHC metadata. It can be disabled
with `pruneUnusedDependencies = false` on `buildAndroidLib` or
`buildNativeLib`.

Measured on a small Flutter/Haskell reference application:

- Linux native bundle: 27.29 MiB / 24 `.so` files without pruning,
  21.81 MiB / 18 `.so` files with pruning.
- Android arm64-v8a bundle: 37.57 MiB / 17 `.so` files without pruning,
  28.70 MiB / 11 `.so` files with pruning.

The pruned libraries were `haskell-ffi-th`, `template-haskell`, `ghc-boot-th`,
`pretty`, `array`, and `deepseq`.

### Nix-managed Flutter and Android SDKs

The Flutter dev shells no longer require a manually installed Flutter SDK or
Android SDK.  Both are provided by Nix.

- `nix/flutter-sdk.nix`: wraps `pkgs.flutter` in a writable symlink farm
  where only `packages/flutter_tools/gradle/` is a real directory (needed
  because Gradle 9 validates the `includeBuild` project directory is
  writable).
- `nix/android-sdk.nix`: uses `androidenv.composeAndroidPackages` with
  pinned NDK/build-tools/CMake versions matching Flutter 3.44 defaults, used
  directly from the Nix store (read-only). Pinning to Flutter's own
  requested versions means AGP never perceives a missing component and
  never needs to write to the SDK root, so no wrapper is needed here.
- All dev shells and templates materialise the Flutter farm in `shellHook`, export
  `ANDROID_HOME`/`ANDROID_SDK_ROOT` to the Android SDK's Nix store path, and
  write `android/local.properties` automatically.

The `android_sdk.accept_license` config is now set in all nixpkgs imports.
See `docs/nix-managed-sdks.md` for design details.

### RTS initialization contract documented

Documented the runtime initialization contract: each consumer package owns a
`cbits/haskell_runtime.c` shim (calling `hs_init` via `pthread_once`) and
declares it via `c-sources` in the `.cabal` file. The templates already ship
this file out of the box. See `docs/runtime-auto-init.md`.
