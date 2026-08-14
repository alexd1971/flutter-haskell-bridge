{ pkgs
, bridgeLib
, ghcVersion
, ffiPackageFile
, manifestFile ? "ffi-manifest.json"
, localPackages
, name
, flutterBridgeDir
, linkMode
}:

# Native desktop artifact builder consumed by flutter-artifacts.nix.
# `libDir` is the Flutter platform directory, and `package` is a lazy Nix
# derivation built only when native artifacts are requested.
let
  libDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${flutterBridgeDir}/macos/lib"
    else if pkgs.stdenv.hostPlatform.isLinux then
      "${flutterBridgeDir}/linux/lib"
    else
      throw "Unsupported native Flutter desktop system: ${pkgs.stdenv.hostPlatform.system}";
in
{
  inherit libDir;

  package =
    bridgeLib.buildNativeLib {
      inherit ghcVersion manifestFile localPackages name;
      packageFile = ffiPackageFile;
      nativeLinkMode = linkMode;
    };
}
