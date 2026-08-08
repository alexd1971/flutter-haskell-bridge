# Flutter Haskell Plugin Scaffold

This template is a starting point for a Flutter plugin backed by a
cross-compiled Haskell library.

It is intended for a reusable Flutter plugin package. The local Haskell
packages stay next to the plugin and `bundle-libs` copies generated native
artifacts into the Flutter plugin layout.

Layout:

```text
haskell-lib/              Reusable Haskell domain library
haskell-ffi/              Plugin FFI adapter and TH export declarations
flutter_haskell_plugin/   Flutter plugin package that owns the Dart API
```

`haskell-lib/` is only the template's local example domain package. A real
plugin can depend on any external Haskell library instead and wire it into the
flake as a local or source-repository package dependency.

## Usage Workflow

The flake inputs are GitHub inputs (`nixpkgs`, `template-haskell-cross`,
`haskell-ffi-th`, and `flutter-haskell-bridge`).

Enter the development shell first:

```bash
nix develop
```

The normal edit/build loop is:

1. Put reusable Haskell logic in `haskell-lib/`, or depend on an external
   Haskell library.
2. Define exported FFI functions in `haskell-ffi/`. The adapter can use
   [`haskell-ffi-th`](https://github.com/alexd1971/haskell-ffi-th) to declare
   exported symbols and generate the FFI manifest consumed by the Dart API
   generator.
3. Run `nix run .#bundle-libs`.
4. Run Flutter checks from `flutter_haskell_plugin/`.

### Build artifacts

The flake builds Haskell artifacts through `template-haskell-cross`, then keeps
Flutter-specific packaging in this project:

- `packages.${system}.android-jni-libs`: Android runtime `.so` bundle under
  `arm64-v8a/`.
- `packages.${system}.native-shared-libs`: desktop/native runtime shared
  library bundle for the current Nix system.
- `packages.${system}.dart-api`: generated Dart FFI wrapper. The standalone
  package output uses the Android manifest; `bundle-libs -- native` generates
  the same wrapper from the native manifest while copying artifacts.
- `apps.${system}.regen-haskell-nix`: regenerates Cabal-derived Nix expressions.
- `apps.${system}.bundle-libs`: builds selected outputs and copies them into
  the Flutter plugin layout. It runs `regen-haskell-nix` first and accepts
  `all`, `android`, or `native`; `all` is the default.

The Nix package output keeps artifacts flat:

```text
result/
  arm64-v8a/   # android-jni-libs
    *.so
  lib/         # native-shared-libs
    *.so or *.dylib
```

Synchronize generated artifacts into the Flutter plugin:

```bash
nix run .#bundle-libs
nix run .#bundle-libs -- android
nix run .#bundle-libs -- native
```

This command copies:

- `arm64-v8a/*.so` to
  `flutter_haskell_plugin/android/src/main/jniLibs/arm64-v8a/`;
- native `.so`/`.dylib` files to `flutter_haskell_plugin/linux/lib/` or
  `flutter_haskell_plugin/macos/lib/`;
- `flutter_haskell_api.dart` to `flutter_haskell_plugin/lib/` from the selected
  target manifest.

`bundle-libs -- all` builds Android and native artifacts. The FFI manifest is
generated once per target build, but the Dart API file is written only once.
Android and native builds export the same symbols, so the Dart API is not
target-specific.

## Run checks

```bash
nix run .#bundle-libs
cd flutter_haskell_plugin
flutter pub get
flutter analyze
```

`bundle-libs` copies generated runtime artifacts into
`flutter_haskell_plugin/`. Commit those copied artifacts and the generated Dart
API if the plugin should be buildable by ordinary Flutter tooling without Nix.
