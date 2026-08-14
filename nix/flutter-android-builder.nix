{ bridgeLib
, ghcVersion
, ffiPackageFile
, manifestFile ? "ffi-manifest.json"
, localPackages
, name
, target
, abi
, linkMode
}:

# Android artifact builder consumed by flutter-artifacts.nix.
# `package` is a lazy Nix derivation; it is built only when the selected app or
# package needs Android JNI libraries.
{
  inherit abi;

  package =
    bridgeLib.buildAndroidLib {
      inherit ghcVersion manifestFile localPackages name target;
      packageFile = ffiPackageFile;
      androidAbi = abi;
      androidLinkMode = linkMode;
    };
}
