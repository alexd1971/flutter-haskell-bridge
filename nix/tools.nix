{ pkgs }:

let
  flutterSdk = import ./flutter-sdk.nix { inherit pkgs; };
  androidSdk = import ./android-sdk.nix { inherit pkgs; };
in
{
  dartFfiGenerator =
    pkgs.writeShellScriptBin "flutter-haskell-generate-dart-ffi" ''
      exec ${pkgs.python3}/bin/python3 ${../tools/generate-dart-ffi-api.py} "$@"
    '';

  inherit flutterSdk androidSdk;
}
