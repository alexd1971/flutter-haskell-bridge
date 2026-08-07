{ pkgs }:

let
  # Flutter 3.44 defaults: compileSdk/targetSdk 36, NDK 28.2.13676358.
  # See FlutterExtension.kt in flutter_tools/gradle.  Pin the NDK version
  # explicitly so the SDK matches what Flutter expects regardless of which
  # nixpkgs revision resolves it.  Pinning to Flutter's own defaults means
  # AGP never perceives a missing component and never attempts to write to
  # the (read-only) SDK root, so no writable-farm wrapper is needed here
  # (unlike the Flutter SDK, see `nix/flutter-sdk.nix`).
  composed = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
    includeSources = false;
    includeSystemImages = false;
    includeEmulator = false;
    platformVersions = [ "36" ];
    ndkVersions = [ "28.2.13676358" ];
    buildToolsVersions = [ "36.0.0" ];
    # AGP 9's native build defaults to CMake 3.22.1; Flutter 3.44 ships 4.1.0.
    cmakeVersions = [ "3.22.1" "4.1.0" ];
  };
in
{
  # The Nix store Android SDK derivation (read-only).
  sdk = composed.androidsdk;

  # The read-only SDK root path, for direct use as ANDROID_HOME / sdk.dir.
  sdkRoot = "${composed.androidsdk}/libexec/android-sdk";
}
