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
haskell-packages.nix      Plugin-specific Haskell package wiring
flutter_plugin/           Flutter plugin package that owns the Dart API
```

`haskell-lib/` is only the template's local example domain package. A real
plugin can depend on any external Haskell library instead. Put plugin-specific
Haskell package wiring in `haskell-packages.nix`; the main `flake.nix` is
intended to stay generic.

`haskell-packages.nix` separates the FFI adapter from the packages it depends
on:

```nix
{
  ffiAdapterPackage = {
    packageDir = "haskell-ffi";
    packageFile = ./haskell-ffi/nix/generated/haskell-ffi.nix;
  };

  ffiDependencyPackages = {
    haskell-lib = {
      packageDir = "haskell-lib";
      packageFile = ./haskell-lib/nix/generated/haskell-lib.nix;
    };
  };
}
```

### Haskell library dependencies

The `haskell-ffi/` package is the FFI adapter. It can depend on Haskell domain
libraries in several ways:

- Hackage/package-set dependency: add it only to `haskell-ffi.cabal`. No
  `haskell-packages.nix` entry is needed if the selected GHC package set already
  provides it.
- Local package: add it to `ffiDependencyPackages` with a generated
  `packageFile`. The attribute name must match the Cabal dependency name. For
  example, the template's `haskell-lib` entry points to
  `./haskell-lib/nix/generated/haskell-lib.nix`.
- External package with a pre-generated Nix expression: add it to
  `ffiDependencyPackages` with `regenerate = false`, so `regen-haskell-nix`
  does not try to run `cabal2nix` on a local directory.

## Usage Workflow

Enter the development shell first:

```bash
nix develop
```

The normal edit/build loop is:

1. Put reusable Haskell logic in `haskell-lib/`, or replace it with another
   local/external Haskell library in `haskell-packages.nix`.
2. Define exported FFI functions in `haskell-ffi/`. The adapter can use
   [`haskell-ffi-th`](https://github.com/alexd1971/haskell-ffi-th) to declare
   exported symbols and generate the FFI manifest consumed by the Dart API
   generator.
3. Run `nix run .#bundle-libs`.
4. Run Flutter checks from `flutter_plugin/`.

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
  `flutter_plugin/android/src/main/jniLibs/arm64-v8a/`;
- native `.so`/`.dylib` files to `flutter_plugin/linux/lib/` or
  `flutter_plugin/macos/lib/`;
- `bridge.dart` to `flutter_plugin/lib/` from the selected target manifest.

`bundle-libs -- all` builds Android and native artifacts. The FFI manifest is
generated once per target build, but the Dart API file is written only once.
Android and native builds export the same symbols, so the Dart API is not
target-specific.

## Run checks

```bash
nix run .#bundle-libs
cd flutter_plugin
flutter pub get
flutter analyze
```

`bundle-libs` copies generated runtime artifacts into
`flutter_plugin/`. Commit those copied artifacts and the generated Dart
API if the plugin should be buildable by ordinary Flutter tooling without Nix.

## Release builds

This template intentionally does not define final application outputs such as
`nix build .#native`, `nix build .#android`, or `nix build .#web`.

`bundle-libs` is responsible for the Flutter/Haskell bridge artifacts: native
libraries, Android JNI libraries, and the generated Dart FFI API. Final Flutter
plugin checks and application release builds are delegated to Flutter tooling:

```bash
cd flutter_plugin
flutter analyze
```

If a downstream application wants Nix release outputs, add them in that
application repository where the release model is known:

- Linux/native can use `buildFlutterApplication` from nixpkgs after the bridge
  artifacts are bundled into the source tree used by the build.
- Android needs a project-specific Flutter/Gradle build derivation.
- Web requires a web-safe application API, usually an HTTP implementation
  selected instead of the FFI implementation.
