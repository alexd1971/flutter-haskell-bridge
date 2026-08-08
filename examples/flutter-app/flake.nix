{
  description = "Flutter app with an embedded Haskell-backed bridge plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    th-cross.url = "github:alexd1971/template-haskell-cross";
    haskell-ffi-th.url = "github:alexd1971/haskell-ffi-th";
  };

  outputs = { self, nixpkgs, th-cross, haskell-ffi-th, ... }:
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
      artifactOutputsFor = system:
        let
          pkgs = importNixpkgs system;
          bridge = import ../../nix/bridge-lib.nix { inherit pkgs th-cross system; };
          tools = import ../../nix/tools.nix { inherit pkgs; };
        in
        import ../../nix/flutter-artifacts.nix {
          inherit pkgs ghcVersion androidAbi;
          haskellFfiTh = haskell-ffi-th;
          bridgeLib = bridge;
          dartFfiGenerator = tools.dartFfiGenerator;
          androidTarget = target;
          ffiLibraryName = "flutter_haskell_app";
          flutterPackageDir = "flutter-haskell-bridge";
          packageFile = ./haskell-ffi/nix/generated/haskell-ffi.nix;
          localHaskellPackages = {
            haskell-lib = {
              packageFile = ./haskell-lib/nix/generated/haskell-lib.nix;
            };
          };
        };
    in
    {
      packages = forAllSystems (system: (artifactOutputsFor system).packages);

      apps = forAllSystems (system: (artifactOutputsFor system).apps);

      devShells = forAllSystems (system:
        let
          pkgs = importNixpkgs system;
          tools = import ../../nix/tools.nix { inherit pkgs; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.android-tools
              pkgs.cabal-install
              pkgs.cabal2nix
              pkgs.jdk17
              tools.dartFfiGenerator
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
Flutter Haskell app example shell

Common commands:
  nix run .#regen-haskell-nix
  nix run .#bundle-libs
  cd flutter-app
  flutter pub get
  flutter run

Android SDK/device configuration is still owned by Flutter/Android tooling.
Use a mutable Flutter SDK checkout for `flutter run`; Gradle cannot use the
read-only Flutter SDK from the Nix store as an included build.
EOF
            '';
          };
        });
    };
}
