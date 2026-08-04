{ pkgs }:

{
  dartFfiGenerator =
    pkgs.writeShellScriptBin "flutter-haskell-generate-dart-ffi" ''
      exec ${pkgs.python3}/bin/python3 ${../tools/generate-dart-ffi-api.py} "$@"
    '';
}
