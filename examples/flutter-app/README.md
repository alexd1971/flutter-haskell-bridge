# Flutter Haskell App Scaffold

This application has an embedded Haskell-backed Flutter bridge.

Layout:

```text
haskell-lib/             Reusable Haskell domain library
  src/Lib.hs             Haskell implementation API
haskell-ffi/             Application FFI adapter and TH export declarations
  cbits/                 RTS initialization shim
bridge/                  Flutter package with Dart FFI and Android JNI libraries
lib/                     Flutter application code
```

Build and synchronize generated artifacts:

```bash
nix run .#sync-haskell-artifacts
```

The sync command copies:

- Haskell Android `.so` files into `bridge/android/src/main/jniLibs/arm64-v8a/`;
- Dart FFI API derived from the `haskell-ffi` export splice into `bridge/lib/`.

The application depends on the embedded plugin through a local path dependency.

## Local Example

This development example imports bridge code from the parent checkout and uses
a local `th-cross` checkout plus a sibling `haskell-ffi-th` checkout:

```nix
th-cross.url = "path:/home/alexey/Projects/flutter-bridges/th-cross";
haskell-ffi-th.url = "path:/home/alexey/Projects/flutter-bridges/haskell-ffi-th";
```

The sync command regenerates Nix expressions for all local Haskell packages
before building artifacts. To run only that step:

```bash
nix run .#regen-haskell-nix
```

Then run the Flutter app from this directory:

```bash
flutter pub get
flutter run
```
