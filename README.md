# Flutter Haskell Bridge

Flutter/Haskell integration helpers built on top of
[`template-haskell-cross`](https://github.com/alexd1971/template-haskell-cross).

This repository is intentionally separate from `template-haskell-cross`:

- `template-haskell-cross` builds Haskell packages with Template Haskell under
  cross-GHC.
- `flutter-haskell-bridge` packages those artifacts for Flutter plugins/apps and
  owns Flutter-specific layout, RPATH rewriting, and Dart FFI API generation.

## Usage Workflow

Create an application from the app template:

```bash
mkdir my-haskell-flutter-app
cd my-haskell-flutter-app
nix flake init -t github:alexd1971/flutter-haskell-bridge#flutter-app
```

Or create a reusable Flutter plugin:

```bash
mkdir my-haskell-flutter-plugin
cd my-haskell-flutter-plugin
nix flake init -t github:alexd1971/flutter-haskell-bridge#flutter-plugin
```

Enter the Nix development shell before running Flutter or artifact commands:

```bash
nix develop
```

The normal downstream edit/build loop is:

1. Implement or depend on Haskell domain code. The templates include a local
   `haskell-lib/` only as a starting point; a real project can use any external
   Haskell library instead and wire it through `haskell-packages.nix`.
2. Export the FFI surface from `haskell-ffi/`. The adapter can use
   [`haskell-ffi-th`](https://github.com/alexd1971/haskell-ffi-th) to declare
   exported symbols and generate the FFI manifest consumed by the Dart API
   generator.
3. Run `nix run .#bundle-libs`.
4. Run the Flutter app or plugin checks.

This is the same workflow used by `tic-tac-toe-hs`.

### Bundle artifacts

```bash
nix run .#bundle-libs
```

`bundle-libs` regenerates Cabal-derived Nix expressions, builds selected
Haskell artifacts, copies them into the Flutter package layout, and writes one
generated Dart FFI API file. It accepts:

```bash
nix run .#bundle-libs -- all      # default: android + native
nix run .#bundle-libs -- android  # Android JNI libs only
nix run .#bundle-libs -- native   # desktop/native libs only
```

The generated Dart API is target-independent: Android and native builds export
the same symbols. Target-specific manifests are still produced independently,
because each Haskell target is compiled separately.

For Android-only work:

```bash
nix run .#bundle-libs -- android
cd flutter-app
flutter pub get
flutter run
```

For Linux desktop work:

```bash
nix run .#bundle-libs -- native
cd flutter-app
flutter pub get
flutter run -d linux
```

For a reusable plugin template, run Flutter commands inside the plugin package:

```bash
cd flutter_plugin
flutter pub get
flutter analyze
```

`bundle-libs` copies generated runtime artifacts into the Flutter layout. If a
downstream project should be buildable by ordinary Flutter tooling without Nix,
commit those copied artifacts together with the generated Dart API.

### Haskell library dependencies

The `haskell-ffi/` package is the FFI adapter. It can depend on Haskell domain
libraries in several ways:

- Hackage/package-set dependency: add it only to `haskell-ffi.cabal`. No
  `haskell-packages.nix` entry is needed if the selected GHC package set already
  provides it.
- Local package: add it to `haskell-packages.nix` with a generated
  `packageFile`. The attribute name must match the cabal dependency name.
- External package with a pre-generated Nix expression: add it to
  `haskell-packages.nix` with `regenerate = false`, so `regen-haskell-nix` does
  not try to run `cabal2nix` on a local directory.

The templates include `haskell-lib/` only as a local example.

Template flake inputs are GitHub inputs:

- `github:NixOS/nixpkgs`
- `github:alexd1971/template-haskell-cross`
- `github:alexd1971/haskell-ffi-th`
- `github:alexd1971/flutter-haskell-bridge`

## Public API

The flake exposes:

- `lib.${system}.buildAndroidLib`: builds Android JNI artifacts from a Haskell
  package compiled by `template-haskell-cross`.
- `lib.${system}.buildNativeLib`: builds desktop/native shared library
  artifacts for the current Nix system with the native GHC package set.
- `lib.${system}.tools`: a Flutter SDK wrapper that materialises a writable
  symlink farm on first use (so Gradle can use the read-only Nix store SDK),
  plus a read-only reference to a Nix-composed Android SDK. See
  `docs/nix-managed-sdks.md`.
- `packages.${system}.dart-ffi-generator`: small generator for Dart FFI wrapper
  code from a JSON FFI manifest.
- `templates.flutter-app`: Flutter app scaffold with an embedded bridge package,
  app-specific `haskell-packages.nix`, example local `haskell-lib/` package,
  and local `haskell-ffi/` adapter package.
- `templates.flutter-plugin`: standalone Flutter plugin scaffold with an
  app-specific `haskell-packages.nix` and example local `haskell-lib/` package.

The default template is `flutter-app`.

Both templates provide `devShells.default` that supply Flutter and Android SDKs
from Nix — no manual SDK installation is required. Templates build both Android
JNI libraries and native desktop shared libraries for the host system.

## Local Development

When hacking on local checkouts, override the GitHub inputs explicitly:

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
