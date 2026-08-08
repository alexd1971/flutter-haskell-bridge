{ pkgs
, bridgeLib
, dartFfiGenerator
, haskellFfiTh
, ghcVersion
, androidTarget ? "aarch64-android"
, androidAbi ? "arm64-v8a"
, ffiLibraryName
, flutterPackageDir
, packageDir ? "haskell-ffi"
, packageFile
, localHaskellPackages ? { }
, regeneratePackages ?
    (pkgs.lib.mapAttrsToList
      (packageName: localPackage: {
        packageDir = localPackage.packageDir or packageName;
        outputFile =
          localPackage.outputFile or (builtins.baseNameOf localPackage.packageFile);
      })
      (pkgs.lib.filterAttrs
        (_: localPackage: localPackage.regenerate or true)
        localHaskellPackages))
    ++ [
      {
        inherit packageDir;
        outputFile = builtins.baseNameOf packageFile;
      }
    ]
, dartApiFile ? "flutter_haskell_api.dart"
}:

let
  manifestFile = "ffi-manifest.json";

  nativeLibDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${flutterPackageDir}/macos/lib"
    else if pkgs.stdenv.hostPlatform.isLinux then
      "${flutterPackageDir}/linux/lib"
    else
      throw "Unsupported native Flutter desktop system: ${pkgs.stdenv.hostPlatform.system}";

  localPackages =
    {
      haskell-ffi-th = {
        packageFile = haskellFfiTh + /nix/generated/haskell-ffi-th.nix;
      };
    }
    // localHaskellPackages;

  packages = rec {
    android-jni-libs =
      bridgeLib.buildAndroidLib {
        inherit ghcVersion androidAbi packageFile manifestFile localPackages;
        target = androidTarget;
        name = ffiLibraryName;
      };

    native-shared-libs =
      bridgeLib.buildNativeLib {
        inherit ghcVersion packageFile manifestFile localPackages;
        name = ffiLibraryName;
      };

    dart-api =
      pkgs.runCommand "${ffiLibraryName}-dart-api" { } ''
        mkdir -p "$out"
        ${dartFfiGenerator}/bin/flutter-haskell-generate-dart-ffi \
          --spec ${android-jni-libs}/${manifestFile} \
          --out "$out/${dartApiFile}"
      '';

    default = android-jni-libs;
  };

  regenScript =
    let
      regenerateCommand = package:
        if builtins.isAttrs package then
          "regenerate ${pkgs.lib.escapeShellArg package.packageDir} ${pkgs.lib.escapeShellArg package.outputFile}"
        else
          "regenerate ${pkgs.lib.escapeShellArg package} \"$(basename ${pkgs.lib.escapeShellArg package}).nix\"";
    in
    pkgs.writeShellScriptBin "regen-haskell-nix" ''
      set -euo pipefail

      regenerate() {
        local package="$1"
        local output_file="$2"
        mkdir -p "$package/nix/generated"
        (
          cd "$package/nix/generated"
          ${pkgs.cabal2nix}/bin/cabal2nix ../.. > "$output_file"
        )
      }

      ${pkgs.lib.concatMapStringsSep "\n" regenerateCommand regeneratePackages}
    '';

  bundleLibsScript =
    pkgs.writeShellScriptBin "bundle-libs" ''
      set -euo pipefail

      mode="''${1:-all}"
      case "$mode" in
        all|android|native)
          ;;
        *)
          echo "usage: bundle-libs [all|android|native]" >&2
          exit 2
          ;;
      esac

      ${regenScript}/bin/regen-haskell-nix

      dart_api_manifest=
      if [ "$mode" = all ] || [ "$mode" = android ]; then
        jni_libs="$(nix build --no-link --print-out-paths .#android-jni-libs)"
        dart_api_manifest="$jni_libs/${manifestFile}"

        target_dir="${flutterPackageDir}/android/src/main/jniLibs/${androidAbi}"
        if [ -e "$target_dir" ]; then
          chmod -R u+w "$target_dir"
          rm -rf "$target_dir"
        fi
        mkdir -p "$(dirname "$target_dir")"
        cp -R "$jni_libs/${androidAbi}" "$target_dir"
        chmod -R u+w "$target_dir"
      fi

      if [ "$mode" = all ] || [ "$mode" = native ]; then
        native_libs="$(nix build --no-link --print-out-paths .#native-shared-libs)"
        if [ "$mode" = native ]; then
          dart_api_manifest="$native_libs/${manifestFile}"
        fi

        native_target_dir="${nativeLibDir}"
        if [ -e "$native_target_dir" ]; then
          chmod -R u+w "$native_target_dir"
          rm -rf "$native_target_dir"
        fi
        mkdir -p "$native_target_dir"
        cp -R "$native_libs/lib/." "$native_target_dir/"
        chmod -R u+w "$native_target_dir"
      fi

      dart_api_dir="$(mktemp -d)"
      ${dartFfiGenerator}/bin/flutter-haskell-generate-dart-ffi \
        --spec "$dart_api_manifest" \
        --out "$dart_api_dir/${dartApiFile}"
      cp "$dart_api_dir/${dartApiFile}" \
        "${flutterPackageDir}/lib/${dartApiFile}"
    '';
in
{
  inherit packages;

  apps = {
    regen-haskell-nix = {
      type = "app";
      program = "${regenScript}/bin/regen-haskell-nix";
    };

    bundle-libs = {
      type = "app";
      program = "${bundleLibsScript}/bin/bundle-libs";
    };
  };
}
