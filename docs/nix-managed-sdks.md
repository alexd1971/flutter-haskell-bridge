# Nix-managed Flutter and Android SDKs

## Problem

The Flutter dev shells previously required a manually installed Flutter SDK
checkout (e.g. `/home/alexey/develop/flutter`) and a system Android SDK
(`/home/alexey/Android/Sdk`).  The `shellHook` actively warned the user when
`flutter` resolved to a Nix store path, because `flutter run` / Gradle could
not use the read-only Nix Flutter package as an included build.

This broke the "Nix is the source of truth" convention: a fresh checkout
needed at least two external SDK installations before `flutter build apk`
could work.

## Context

The Nix store's read-only Flutter package conflicts with Flutter's build
model: Flutter's `settings.gradle.kts` does
`includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`, and Gradle 9
(used by AGP 9, the default for Flutter 3.44+) validates that the included
build's project directory is writable *before* processing its settings
script. The nixpkgs `gradle-flutter-tools-wrapper` patch redirects `.gradle`
and `build` directories to `$HOME/.cache`, but the project directory check
happens earlier and cannot be redirected the same way.

The Android SDK does not have an equivalent problem in this setup. AGP's
`SdkManager` only writes to the SDK root (`.knownPackages`,
`source.properties`, `licenses/`) when it decides a component is missing and
needs installing. As long as the Nix-composed SDK's pinned versions
(platform, NDK, build-tools, CMake) exactly match what Flutter's Gradle build
requests (`flutter.compileSdkVersion`, `flutter.ndkVersion`, etc.) and license
acceptance is baked in via `android_sdk.accept_license = true`, AGP never
perceives a missing component and never attempts to write to the SDK root.
This was verified empirically for both debug and release builds. So the
Android SDK is used directly from the Nix store, read-only — no wrapper
needed.

## Solution

### Flutter SDK wrapper (`nix/flutter-sdk.nix`)

A `flutter` wrapper script that, on first invocation, materialises a writable
SDK farm in `$XDG_CACHE_HOME/flutter-nix/<hash>/`:

- All top-level entries are symlinks to the Nix Flutter store path.
- `packages/` is a real directory so `flutter_tools/gradle/` can be made
  writable inside it.
- `packages/flutter_tools/gradle/` is a real directory whose *contents* are
  symlinks to the store.  Gradle sees a writable project directory and
  proceeds normally.

A stamp file (`.nix-flutter-stamp`) records the Nix store path.  When it
changes (e.g. after `nixpkgs` update), the farm is rebuilt.

The wrapper sets `FLUTTER_ROOT` to the writable farm and delegates to the
original Nix Flutter binary.  A companion `flutter-sdk-path` script
materialises the farm and prints its path, for embedding in
`local.properties`.

### Android SDK (`nix/android-sdk.nix`)

Uses `androidenv.composeAndroidPackages` with pinned versions matching
Flutter 3.44 defaults:

- Platform 36 (compileSdk/targetSdk)
- NDK 28.2.13676358
- Build-tools 36.0.0
- CMake 3.22.1 (AGP 9 native build default) and 4.1.0 (Flutter 3.44)

Exposed as `sdk` (the derivation) and `sdkRoot` (its
`libexec/android-sdk` path), used directly and read-only — no wrapper.

### Dev shell integration

The `devShells.default` in each consumer flake:

1. Adds the `flutter` wrapper and `flutter-sdk-path` to `packages`.
2. In `shellHook`, materialises the Flutter farm, exports `ANDROID_HOME` /
   `ANDROID_SDK_ROOT` to the Android SDK's Nix store path, and writes
   `android/local.properties` accordingly.

The `local.properties` file is `.gitignore`d, so it is regenerated on each
`nix develop` without polluting the working tree.

## Trade-offs

- **Cache size.**  The Flutter writable farm is small (symlinks + a few real
  directories), but the underlying Nix store path is large. This is
  unavoidable: the SDK must exist somewhere.
- **First-run latency.**  The first `nix develop` in a clean cache
  materialises the Flutter farm, which takes a moment. Subsequent runs are
  instant. The Android SDK needs no materialisation.
- **Nixpkgs version drift.**  The `flutter-haskell-bridge` flake follows the
  consumer's `nixpkgs` input, so the Flutter/Android SDK versions are
  determined by the consumer's `nixpkgs` revision.  The pinned Android SDK
  component versions (NDK, build-tools, CMake) are hardcoded to match
  Flutter 3.44 defaults; a Flutter upgrade may require updating them — and if
  a future Flutter version requests a component that isn't pinned here, AGP
  may need to write to the SDK root again, which would require reintroducing
  a writable farm for the Android SDK.
