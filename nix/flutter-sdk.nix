{ pkgs }:

let
  nixFlutter = pkgs.flutter;

  # Derive a stable identifier from the Nix store path so a new SDK version
  # triggers a fresh writable farm instead of reusing a stale one.
  storeHash = builtins.substring 0 16 (builtins.hashString "sha256" "${nixFlutter}");

  # The Nix Flutter SDK is read-only.  Gradle 9 (used by AGP 9, the default
  # for Flutter 3.44+) validates that the ``includeBuild`` project directory
  # is writable before processing its settings script.  The nixpkgs
  # ``gradle-flutter-tools-wrapper`` patch already redirects ``.gradle`` and
  # ``build`` to ``$HOME/.cache``, but the project directory check happens
  # earlier and cannot be redirected the same way.
  #
  # The workaround is a *writable symlink farm*: a directory that mirrors the
  # Nix Flutter SDK via symlinks, except ``packages/flutter_tools/gradle/``
  # which is a real (writable) directory whose *contents* are symlinks to the
  # store.  Gradle sees a writable project directory and proceeds normally.
  flutterWrapper = pkgs.writeShellScriptBin "flutter" ''
    set -euo pipefail

    nix_flutter="${nixFlutter}"
    cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}/flutter-nix"
    sdk_dir="$cache_root/${storeHash}"

    # Rebuild the farm when the store path changes or on first use.
    marker="$sdk_dir/.nix-flutter-stamp"
    if [ ! -f "$marker" ] || [ "$(<"$marker")" != "$nix_flutter" ]; then
      rm -rf "$sdk_dir"
      mkdir -p "$sdk_dir"

      # Top-level entries: direct symlinks to the store.
      for item in "$nix_flutter"/*; do
        ln -s "$item" "$sdk_dir/$(basename "$item")"
      done

      # ``packages`` must be a real directory so we can make
      # ``flutter_tools/gradle`` writable inside it.
      rm "$sdk_dir/packages"
      mkdir -p "$sdk_dir/packages/flutter_tools/gradle"

      for item in "$nix_flutter"/packages/*; do
        name="$(basename "$item")"
        if [ "$name" != "flutter_tools" ]; then
          ln -s "$item" "$sdk_dir/packages/$name"
        fi
      done

      for item in "$nix_flutter"/packages/flutter_tools/*; do
        name="$(basename "$item")"
        if [ "$name" != "gradle" ]; then
          ln -s "$item" "$sdk_dir/packages/flutter_tools/$name"
        fi
      done

      # ``gradle`` is a real directory so Gradle can write ``.gradle`` and
      # ``build`` inside it.  Individual files remain symlinks to the store.
      shopt -s dotglob nullglob
      for item in "$nix_flutter"/packages/flutter_tools/gradle/*; do
        ln -s "$item" "$sdk_dir/packages/flutter_tools/gradle/$(basename "$item")"
      done
      shopt -u dotglob nullglob

      printf '%s' "$nix_flutter" > "$marker"
    fi

    export FLUTTER_ROOT="$sdk_dir"
    exec "${nixFlutter}/bin/flutter" "$@"
  '';

  # A script that prints the writable SDK path, for embedding in
  # ``local.properties`` or other tooling that needs the path without
  # launching Flutter.
  flutterSdkPath = pkgs.writeShellScriptBin "flutter-sdk-path" ''
    set -euo pipefail
    cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}/flutter-nix"
    sdk_dir="$cache_root/${storeHash}"
    # Ensure the farm exists before printing the path.
    ${flutterWrapper}/bin/flutter --version >/dev/null 2>&1 || true
    printf '%s\n' "$sdk_dir"
  '';
in
{
  flutter = flutterWrapper;
  flutterSdkPath = flutterSdkPath;
  nixFlutter = nixFlutter;
}
