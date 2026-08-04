{
  description = "Flutter plugin backed by a cross-compiled Haskell FFI library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    th-cross.url = "github:alexd1971/template-haskell-cross";
    haskell-ffi-th.url = "github:alexd1971/haskell-ffi-th";
    flutter-haskell-bridge.url = "github:alexd1971/flutter-haskell-bridge";
    flutter-haskell-bridge.inputs.th-cross.follows = "th-cross";
  };

  outputs = { self, nixpkgs, flutter-haskell-bridge, haskell-ffi-th, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f:
        builtins.listToAttrs
          (map
            (system: {
              name = system;
              value = f system;
            })
            systems);

      ghcVersion = "9.10.3";
      target = "aarch64-android";
      androidAbi = "arm64-v8a";
      importNixpkgs = system:
        import nixpkgs {
          inherit system;
          # Android SDK/NDK packages contain unfree source archives whose
          # package names do not consistently share an `android-sdk-*` prefix.
          config.allowUnfree = true;
        };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = importNixpkgs system;
          packageFile = ./haskell-ffi/nix/generated/haskell-ffi.nix;
        in
        {
          android-jni-libs =
            flutter-haskell-bridge.lib.${system}.buildHaskellLib {
              inherit ghcVersion target androidAbi packageFile;
              name = "flutter_haskell_plugin";
              manifestFile = "ffi-manifest.json";
              localPackages = {
                haskell-ffi-th = {
                  packageFile = haskell-ffi-th + /nix/generated/haskell-ffi-th.nix;
                };
                haskell-lib = {
                  packageFile = ./haskell-lib/nix/generated/haskell-lib.nix;
                };
              };
            };

          dart-api =
            pkgs.runCommand "flutter-haskell-plugin-dart-api" { } ''
              mkdir -p "$out"
              ${flutter-haskell-bridge.packages.${system}.dart-ffi-generator}/bin/flutter-haskell-generate-dart-ffi \
                --spec ${self.packages.${system}.android-jni-libs}/ffi-manifest.json \
                --out "$out/flutter_haskell_api.dart"
            '';

          default = self.packages.${system}.android-jni-libs;
        });

      apps = forAllSystems (system:
        let
          pkgs = importNixpkgs system;
          regenScript =
            pkgs.writeShellScriptBin "regen-haskell-nix" ''
              set -euo pipefail
              regenerate() {
                local package="$1"
                mkdir -p "$package/nix/generated"
                (
                  cd "$package/nix/generated"
                  ${pkgs.cabal2nix}/bin/cabal2nix ../.. > "$(basename "$package").nix"
                )
              }

              regenerate haskell-lib
              regenerate haskell-ffi
            '';
          syncScript =
            pkgs.writeShellScriptBin "sync-haskell-artifacts" ''
              set -euo pipefail

              ${regenScript}/bin/regen-haskell-nix

              jni_libs="$(nix build --no-link --print-out-paths .#android-jni-libs)"
              dart_api="$(nix build --no-link --print-out-paths .#dart-api)"

              target_dir="flutter_haskell_plugin/android/src/main/jniLibs/${androidAbi}"
              if [ -e "$target_dir" ]; then
                chmod -R u+w "$target_dir"
                rm -rf "$target_dir"
              fi
              mkdir -p "$(dirname "$target_dir")"
              cp -R "$jni_libs/${androidAbi}" "$target_dir"
              chmod -R u+w "$target_dir"

              cp "$dart_api/flutter_haskell_api.dart" \
                flutter_haskell_plugin/lib/flutter_haskell_api.dart
            '';
        in
        {
          regen-haskell-nix = {
            type = "app";
            program = "${regenScript}/bin/regen-haskell-nix";
          };

          sync-haskell-artifacts = {
            type = "app";
            program = "${syncScript}/bin/sync-haskell-artifacts";
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = importNixpkgs system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.android-tools
              pkgs.cabal-install
              pkgs.cabal2nix
              pkgs.jdk17
              flutter-haskell-bridge.packages.${system}.dart-ffi-generator
            ];

            shellHook = ''
              if ! command -v flutter >/dev/null 2>&1; then
                echo "Flutter SDK is not on PATH. Use a normal mutable Flutter checkout, not nixpkgs' read-only Flutter package."
              elif [ "$(readlink -f "$(command -v flutter)")" != "''${FLUTTER_SDK:-}" ] \
                && readlink -f "$(command -v flutter)" | grep -q '^/nix/store/'; then
                echo "Flutter on PATH comes from /nix/store. flutter run needs a mutable Flutter SDK checkout."
                echo "Put your Flutter checkout bin directory before Nix paths, for example: export PATH=/home/alexey/develop/flutter/bin:\$PATH"
              fi

              cat <<'EOF'
Flutter Haskell plugin shell

Common commands:
  nix run .#regen-haskell-nix
  nix run .#sync-haskell-artifacts
  cd flutter_haskell_plugin
  flutter pub get

Android SDK/device configuration is still owned by Flutter/Android tooling.
Use a mutable Flutter SDK checkout for `flutter run`; Gradle cannot use the
read-only Flutter SDK from the Nix store as an included build.
EOF
            '';
          };
        });
    };
}
