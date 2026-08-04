# Flutter Haskell Plugin Scaffold

This template is a starting point for a Flutter plugin backed by a
cross-compiled Haskell library.

Layout:

```text
haskell-lib/              Reusable Haskell domain library
haskell-ffi/              Plugin FFI adapter and TH export declarations
flutter_haskell_plugin/   Flutter plugin package that owns the Dart API
```

The flake builds Haskell artifacts through `template-haskell-cross`, then keeps
Flutter-specific packaging in this project:

- `packages.${system}.android-jni-libs`: Android runtime `.so` bundle under
  `arm64-v8a/`.
- `packages.${system}.dart-api`: generated Dart FFI wrapper.
- `apps.${system}.regen-haskell-nix`: regenerates Cabal-derived Nix expressions.
- `apps.${system}.sync-haskell-artifacts`: builds both outputs and copies them
  into the Flutter plugin layout. It runs `regen-haskell-nix` first.

The Nix package output keeps artifacts flat:

```text
result/
  arm64-v8a/
    *.so
```

Synchronize generated artifacts into the Flutter plugin:

```bash
nix run .#sync-haskell-artifacts
```

This command copies:

- `arm64-v8a/*.so` to
  `flutter_haskell_plugin/android/src/main/jniLibs/arm64-v8a/`;
- `flutter_haskell_api.dart` to `flutter_haskell_plugin/lib/`.
