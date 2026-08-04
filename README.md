# Flutter Haskell Bridge

Flutter/Haskell integration helpers built on top of `template-haskell-cross`.

This repository is intentionally separate from `template-haskell-cross`:

- `template-haskell-cross` builds Haskell packages with Template Haskell under
  cross-GHC.
- `flutter-haskell-bridge` packages those artifacts for Flutter plugins/apps and
  owns Flutter-specific layout, RPATH rewriting, and Dart FFI API generation.

## Public Shape

The flake exposes:

- `lib.${system}.buildHaskellLib`: builds Android JNI artifacts from a Haskell
  package compiled by `template-haskell-cross`.
- `packages.${system}.dart-ffi-generator`: small generator for Dart FFI wrapper
  code from a JSON FFI manifest.
- `templates.flutter-app`: Flutter app scaffold with an embedded bridge package,
  local `haskell-lib/` domain package, and local `haskell-ffi/` adapter package.
- `templates.flutter-plugin`: standalone Flutter plugin scaffold with a local
  `haskell-lib/` package.

The default template is `flutter-app`.

## Local Development

Before this repository is published, use local input overrides:

```bash
nix eval \
  --override-input th-cross path:/path/to/template-haskell-cross \
  .#lib.x86_64-linux \
  --apply builtins.attrNames
```

For the template:

```bash
nix eval \
  --override-input flutter-haskell-bridge path:/path/to/flutter-haskell-bridge \
  --override-input flutter-haskell-bridge/th-cross path:/path/to/template-haskell-cross \
  --override-input haskell-ffi-th path:/path/to/haskell-ffi-th \
  ./templates/flutter-plugin#packages.x86_64-linux.dart-api.name
```
