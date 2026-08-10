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

By default, Android and native bundles prune unused direct `DT_NEEDED` entries
from the root Haskell FFI library before copying recursive runtime
dependencies. This removes build-time Template Haskell libraries from runtime
artifacts when they do not resolve any dynamic symbols needed by the FFI
library. Set `pruneUnusedDependencies = false` in `buildAndroidLib` or
`buildNativeLib` to disable this behaviour for libraries that intentionally
keep a dependency for side effects rather than symbol resolution.

In a small Flutter/Haskell application this reduced raw shared-library bundle
size from 27.29 MiB to 21.81 MiB on Linux (`24` to `18` `.so` files) and from
37.57 MiB to 28.70 MiB on Android arm64-v8a (`17` to `11` `.so` files). The
removed libraries were `haskell-ffi-th`, `template-haskell`, `ghc-boot-th`,
`pretty`, `array`, and `deepseq`.

Native Linux builds can opt into an experimental static-Haskell link mode:

```nix
nativeLinkMode = "static-haskell";
```

This mode builds the final native shared library from package `.dyn_o` archives
and GHC boot-package `.dyn_o` archives. It removes `libHS*.so` runtime
dependencies from the final native artifact. Non-system C dependencies that
remain in `DT_NEEDED`, such as `libgmp` and `libffi`, are copied next to the
final shared library. The custom native GHC used by this mode also builds the
RTS without DWARF unwind and NUMA support, avoiding the `libdw`, `libelf`, and
`libnuma` runtime dependency chain. The first build is expensive because it
needs a native GHC build that preserves boot-package `.dyn_o` files. The
resulting shared library exports the same FFI symbols and has no `NEEDED
libHS*.so` entries. In a small Linux reference bundle, static-Haskell mode with
copied non-system C dependencies originally needed `11` `.so` files; disabling
RTS DWARF unwind and NUMA support reduced that to `3` files: the public FFI
library plus `libffi` and `libgmp`.

Android arm64-v8a builds can opt into the same static-Haskell strategy:

```nix
androidLinkMode = "static-haskell";
```

This mode uses cross-GHC `.dyn_o` archives provided by
`template-haskell-cross`, plus package-level `.dyn_o` archives for the root and
local Haskell packages. It is currently supported for `target =
"aarch64-android"` and `androidAbi = "arm64-v8a"`. In the template app, Android
static-Haskell mode reduced the raw JNI bundle from `8` `.so` files / 26 MiB to
`3` `.so` files / 22 MiB: the public FFI library plus `libffi` and `libgmp`.

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
  package compiled by `template-haskell-cross`. Pass `androidLinkMode =
  "static-haskell"` for Android arm64-v8a to link Haskell packages from
  `.dyn_o` archives instead of bundling `libHS*.so` dependencies.
- `lib.${system}.buildNativeLib`: builds desktop/native shared library
  artifacts for the current Nix system with the native GHC package set. Pass
  `nativeLinkMode = "static-haskell"` on Linux to produce one shared library
  with Haskell packages linked from `.dyn_o` archives instead of bundling
  `libHS*.so` dependencies.
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
