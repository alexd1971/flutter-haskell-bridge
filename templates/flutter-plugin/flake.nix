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
      androidLinkMode = "dynamic";
      nativeLinkMode = "dynamic";
      importNixpkgs = system:
        import nixpkgs {
          inherit system;
          config = {
            # Android SDK/NDK packages contain unfree source archives whose
            # package names do not consistently share an `android-sdk-*` prefix.
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
      artifactOutputsFor = system:
        let
          pkgs = importNixpkgs system;
          haskellPackages = import ./haskell-packages.nix;
          manifestFile = "ffi-manifest.json";
          ffiLibraryName = "flutter_haskell_plugin";
          flutterPackageDir = "flutter_plugin";
          ffiPackageFile = ./haskell-ffi/nix/generated/haskell-ffi.nix;
          localPackages =
            {
              haskell-ffi-th = {
                packageFile = haskell-ffi-th + /nix/generated/haskell-ffi-th.nix;
              };
            }
            // haskellPackages.localHaskellPackages;
          androidBuilder =
            import (flutter-haskell-bridge + /nix/flutter-android-builder.nix) {
              bridgeLib = flutter-haskell-bridge.lib.${system};
              inherit ghcVersion ffiPackageFile manifestFile localPackages;
              name = ffiLibraryName;
              inherit target;
              abi = androidAbi;
              linkMode = androidLinkMode;
            };
          nativeBuilder =
            import (flutter-haskell-bridge + /nix/flutter-native-builder.nix) {
              inherit pkgs;
              bridgeLib = flutter-haskell-bridge.lib.${system};
              inherit ghcVersion ffiPackageFile manifestFile localPackages flutterPackageDir;
              name = ffiLibraryName;
              linkMode = nativeLinkMode;
            };
        in
        import (flutter-haskell-bridge + /nix/flutter-artifacts.nix) {
          inherit pkgs androidBuilder nativeBuilder;
          inherit (haskellPackages) localHaskellPackages;
          dartFfiGenerator = flutter-haskell-bridge.packages.${system}.dart-ffi-generator;
          inherit ffiLibraryName flutterPackageDir manifestFile ffiPackageFile;
        };
    in
    {
      packages = forAllSystems (system: (artifactOutputsFor system).packages);

      apps = forAllSystems (system: (artifactOutputsFor system).apps);

      devShells = forAllSystems (system:
        let
          pkgs = importNixpkgs system;
          tools = flutter-haskell-bridge.lib.${system}.tools;
          flutterSdk = tools.flutterSdk;
          androidSdk = tools.androidSdk;
        in
        {
          default = pkgs.mkShell {
            packages = [
              flutterSdk.flutter
              flutterSdk.flutterSdkPath
              pkgs.cabal-install
              pkgs.cabal2nix
              pkgs.jdk17
              flutter-haskell-bridge.packages.${system}.dart-ffi-generator
            ];

            shellHook = ''
              # Materialise the writable Flutter SDK farm.
              flutter_sdk_path="$(${flutterSdk.flutterSdkPath}/bin/flutter-sdk-path)"

              export ANDROID_HOME="${androidSdk.sdkRoot}"
              export ANDROID_SDK_ROOT="${androidSdk.sdkRoot}"

              cat > flutter_plugin/android/local.properties <<EOF
              sdk.dir=${androidSdk.sdkRoot}
              flutter.sdk=$flutter_sdk_path
              flutter.buildMode=debug
              flutter.versionName=1.0.0
              flutter.versionCode=1
              EOF

              cat <<EOF
              Flutter Haskell plugin shell

              Common commands:
                nix run .#regen-haskell-nix
                nix run .#bundle-libs
                cd flutter_plugin
                flutter pub get

              Flutter SDK:  $flutter_sdk_path
              Android SDK:  ${androidSdk.sdkRoot}
              EOF
            '';
          };
        });
    };
}
