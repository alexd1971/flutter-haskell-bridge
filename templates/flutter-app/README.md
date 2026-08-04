# Flutter Haskell App Scaffold

This template creates a Flutter application with an embedded Haskell-backed
Flutter plugin.

Layout:

```text
haskell-lib/             Reusable Haskell domain library
haskell-ffi/             Application FFI adapter and TH export declarations
bridge/                  Flutter package that bridges Dart and Haskell
lib/                     Flutter app code
```

Build and synchronize generated artifacts:

```bash
nix run .#sync-haskell-artifacts
```

The sync command regenerates Cabal-derived Nix expressions, builds artifacts,
and copies:

- Haskell Android `.so` files into
  `bridge/android/src/main/jniLibs/arm64-v8a/`;
- generated Dart FFI API into `bridge/lib/`.

To regenerate only the Cabal-derived Nix expressions:

```bash
nix run .#regen-haskell-nix
```

The application depends on the embedded plugin through a local path dependency.
