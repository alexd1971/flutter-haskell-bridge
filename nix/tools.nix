{ pkgs }:

let
  flutterSdk = import ./flutter-sdk.nix { inherit pkgs; };
  androidSdk = import ./android-sdk.nix { inherit pkgs; };
  dartTool =
    pkgs.writeShellScriptBin "dart" ''
      set -euo pipefail
      export DASH__SUPPRESS_ANALYTICS=true
      export DART_SUPPRESS_ANALYTICS=true
      export FLUTTER_SUPPRESS_ANALYTICS=true
      if [ -z "''${XDG_CACHE_HOME:-}" ] && [ -n "''${TMPDIR:-}" ]; then
        export XDG_CACHE_HOME="$TMPDIR/flutter-cache"
      fi
      flutter_sdk_path="$(${flutterSdk.flutterSdkPath}/bin/flutter-sdk-path)"
      exec "$flutter_sdk_path/bin/dart" --suppress-analytics "$@"
    '';
in
{
  dartFfiGenerator =
    pkgs.writeShellScriptBin "flutter-haskell-generate-dart-ffi" ''
      set -euo pipefail

      out_file=
      previous_arg=
      for arg in "$@"; do
        if [ "$previous_arg" = "--out" ]; then
          out_file="$arg"
          break
        fi
        previous_arg=
        if [ "$arg" = "--out" ]; then
          previous_arg="--out"
        fi
      done

      ${pkgs.python3}/bin/python3 ${../tools/generate-dart-ffi-api.py} "$@"
      if [ -n "$out_file" ]; then
        ${dartTool}/bin/dart format "$out_file" >/dev/null
      fi
    '';

  pruneUnusedNeeded =
    pkgs.writeShellScriptBin "flutter-haskell-prune-unused-needed" ''
      exec ${pkgs.python3}/bin/python3 ${../tools/prune-unused-needed.py} "$@"
    '';

  dart = dartTool;

  inherit flutterSdk androidSdk;
}
