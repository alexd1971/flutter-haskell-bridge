# Flutter Haskell App Scaffold

This template creates a Flutter application with an embedded Haskell-backed
Flutter plugin.

It is intended to be used as a full application scaffold: the Flutter app
depends on the local `flutter-haskell-bridge/` package, while
`flutter-haskell-bridge/` owns Dart FFI bindings and platform-specific native
library placement.

Layout:

```text
flutter-app/              Flutter application
flutter-haskell-bridge/   Flutter package that bridges Dart and Haskell
haskell-packages.nix      App-specific Haskell package wiring
haskell-ffi/              Application FFI adapter and TH export declarations
haskell-lib/              Example reusable Haskell domain library
```

`haskell-lib/` is only the template's local example domain package. A real
application can depend on any external Haskell library instead. Put
application-specific Haskell package wiring in `haskell-packages.nix`; the main
`flake.nix` is intended to stay generic.

### Haskell library dependencies

The `haskell-ffi/` package is the FFI adapter. It can depend on Haskell domain
libraries in several ways:

- Hackage/package-set dependency: add it only to `haskell-ffi.cabal`. No
  `haskell-packages.nix` entry is needed if the selected GHC package set already
  provides it.
- Local package: add it to `haskell-packages.nix` with a generated
  `packageFile`. The attribute name must match the cabal dependency name. For
  example, the template's `haskell-lib` entry points to
  `./haskell-lib/nix/generated/haskell-lib.nix`.
- External package with a pre-generated Nix expression: add it to
  `haskell-packages.nix` with `regenerate = false`, so `regen-haskell-nix` does
  not try to run `cabal2nix` on a local directory.

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
4. Run the Flutter app from `flutter-app/`.

### Bundle artifacts

The main artifact command is:

```bash
nix run .#bundle-libs
nix run .#bundle-libs -- android
nix run .#bundle-libs -- native
```

The optional argument is `all`, `android`, or `native`; `all` is the default.
The command regenerates Cabal-derived Nix expressions, builds selected
artifacts, and copies:

- Haskell Android `.so` files into
  `flutter-haskell-bridge/android/src/main/jniLibs/arm64-v8a/`;
- Haskell native desktop `.so`/`.dylib` files into
  `flutter-haskell-bridge/linux/lib/` or `flutter-haskell-bridge/macos/lib/`,
  depending on the current Nix system;
- one generated Dart FFI API into `flutter-haskell-bridge/lib/` from the
  selected target manifest.

`bundle-libs -- all` builds Android and native artifacts. The FFI manifest is
therefore generated once per target build, but the Dart API file is written only
once. Android and native builds export the same symbols, so the Dart API is not
target-specific.

To regenerate only the Cabal-derived Nix expressions:

```bash
nix run .#regen-haskell-nix
```

The application depends on the embedded plugin through a local path dependency.

## Run Android

```bash
nix run .#bundle-libs -- android
cd flutter-app
flutter pub get
flutter run
```

## Run Linux desktop

```bash
nix run .#bundle-libs -- native
cd flutter-app
flutter run -d linux
```

`bundle-libs` copies generated runtime artifacts into `flutter-haskell-bridge/`.
Commit those copied artifacts and the generated Dart API if the app should be
buildable by ordinary Flutter tooling without Nix.
