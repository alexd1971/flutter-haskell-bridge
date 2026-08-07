# Changes

## Unreleased

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
- All dev shells (`templates/flutter-app`, `templates/flutter-plugin`,
  `tic-tac-toe-hs`) materialise the Flutter farm in `shellHook`, export
  `ANDROID_HOME`/`ANDROID_SDK_ROOT` to the Android SDK's Nix store path, and
  write `android/local.properties` automatically.

The `android_sdk.accept_license` config is now set in all nixpkgs imports.
See `docs/nix-managed-sdks.md` for design details.

### RTS initialization contract documented

Documented the runtime initialization contract: each consumer package owns a
`cbits/haskell_runtime.c` shim (calling `hs_init` via `pthread_once`) and
declares it via `c-sources` in the `.cabal` file. The templates already ship
this file out of the box. See `docs/runtime-auto-init.md`.
