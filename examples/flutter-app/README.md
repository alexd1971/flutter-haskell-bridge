# Flutter Haskell App Scaffold

This application has an embedded Haskell-backed Flutter bridge.

Layout:

```text
flutter-app/              Flutter application
flutter-haskell-bridge/   Flutter FFI package with Dart FFI and native assets
haskell-packages.nix      Application-specific Haskell package wiring
haskell-ffi/              Application FFI adapter and TH export declarations
  cbits/                  RTS initialization shim
haskell-lib/              Example reusable Haskell domain library
  src/Lib.hs              Haskell implementation API
```

This example keeps the domain code in local `haskell-lib/` and wires it through
`haskell-packages.nix`; downstream applications can use an external Haskell
library instead. The `haskell-ffi/` adapter uses `haskell-ffi-th` to declare
exported symbols and produce the FFI manifest used for Dart API generation.

`haskell-packages.nix` separates the FFI adapter from the packages it depends
on: `ffiAdapterPackage` describes `haskell-ffi/`, while
`ffiDependencyPackages` describes local or overridden dependencies such as
`haskell-lib`.

`haskell-ffi/` can depend on Haskell libraries in three common ways:

- Hackage/package-set dependency: add it only to `haskell-ffi.cabal`.
- Local package: add it to `ffiDependencyPackages` with a generated
  `packageFile`; this example uses that for `haskell-lib`.
- External package with a pre-generated Nix expression: add it to
  `ffiDependencyPackages` with `regenerate = false`.

Bundle generated libraries into the Flutter FFI package layout:

```bash
nix run .#bundle-libs
nix run .#bundle-libs -- android
nix run .#bundle-libs -- native
```

The optional argument is `all`, `android`, or `native`; `all` is the default.
The command copies:

- Haskell Android `.so` files into
  `flutter-haskell-bridge/native_assets/android/arm64-v8a/`;
- Haskell native desktop `.so`/`.dylib` files into
  `flutter-haskell-bridge/native_assets/linux/` or
  `flutter-haskell-bridge/native_assets/macos/`, depending on the current Nix
  system;
- Dart FFI API derived from the selected target's `haskell-ffi` export splice
  into `flutter-haskell-bridge/lib/`.

The application depends on the embedded FFI package through a local path
dependency.

## Local Example

This development example imports bridge code from the parent checkout, but its
external dependencies are GitHub flake inputs:

```nix
th-cross.url = "github:alexd1971/template-haskell-cross";
haskell-ffi-th.url = "github:alexd1971/haskell-ffi-th";
```

`bundle-libs` regenerates Nix expressions for all local Haskell packages before
building artifacts. To run only that step:

```bash
nix run .#regen-haskell-nix
```

Then run the Flutter app from this directory:

```bash
nix develop
cd flutter-app
flutter pub get
flutter run
```
