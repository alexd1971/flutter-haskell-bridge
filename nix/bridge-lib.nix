{ pkgs, th-cross, system }:

let
  androidSystemLibraries = [
    "libandroid.so"
    "libc.so"
    "libdl.so"
    "libEGL.so"
    "libGLESv1_CM.so"
    "libGLESv2.so"
    "libGLESv3.so"
    "libjnigraphics.so"
    "liblog.so"
    "libm.so"
    "libnativewindow.so"
    "libOpenMAXAL.so"
    "libOpenSLES.so"
    "libstdc++.so"
    "libsync.so"
    "libvulkan.so"
    "libz.so"
  ];

  copySharedLibraries =
    { name
    , rootPackage
    , targetGhc
    , androidAbi
    , manifestFile ? null
    }:
    let
      packageClosure = pkgs.closureInfo {
        # A Haskell shared library leaves RTS symbols unresolved. Include the
        # target RTS closure explicitly so its own dynamic dependencies are
        # available to the Android bundle copier.
        rootPaths = [ rootPackage targetGhc ];
      };
    in
    pkgs.runCommand
      "${name}-${androidAbi}-jni-libs"
      {
        nativeBuildInputs = [
          pkgs.patchelf
        ];
      }
      ''
        set -euo pipefail

        output_dir="$out/${androidAbi}"
        mkdir -p "$output_dir"

        candidates="$(mktemp)"
        while IFS= read -r store_path; do
          while IFS= read -r -d "" shared_library; do
            if file "$shared_library" | grep -q 'ARM aarch64'; then
              printf '%s\t%s\n' "$(basename "$shared_library")" "$shared_library" >> "$candidates"
            fi
          done < <(find -L "$store_path" -type f -name '*.so' -print0)
        done < "${packageClosure}/store-paths"

        copied="$(mktemp)"

        is_android_system_library() {
          case "$1" in
            ${pkgs.lib.concatMapStringsSep "|" (libName: "${libName}") androidSystemLibraries})
              return 0
              ;;
            *)
              return 1
              ;;
          esac
        }

        find_candidate() {
          awk -F '\t' -v name="$1" '$1 == name { print $2; exit }' "$candidates"
        }

        copy_with_needed() {
          local source="$1"
          local soname
          soname="$(basename "$source")"

          if grep -Fxq "$soname" "$copied"; then
            return
          fi
          printf '%s\n' "$soname" >> "$copied"

          local destination="$output_dir/$soname"
          cp "$source" "$destination"
          chmod u+w "$destination"
          patchelf --set-rpath '$ORIGIN' "$destination" 2>/dev/null || true

          while IFS= read -r needed; do
            if is_android_system_library "$needed"; then
              continue
            fi

            local needed_source
            needed_source="$(find_candidate "$needed")"
            if [ -n "$needed_source" ]; then
              copy_with_needed "$needed_source"
            fi
          done < <(patchelf --print-needed "$destination" 2>/dev/null || true)
        }

        target_rts="$(find -L ${targetGhc} -type f -name 'libHSrts-*_thr-ghc*.so' -print -quit)"
        if [ -z "$target_rts" ]; then
          echo "Could not find the threaded target GHC RTS" >&2
          exit 1
        fi

        while IFS= read -r root_library; do
          copy_with_needed "$root_library"
          copy_with_needed "$target_rts"

          # Cabal libraries rely on the final executable to link the RTS.
          # Dart loads this library directly, so make the dependency explicit.
          patchelf --add-needed "$(basename "$target_rts")" "$output_dir/$(basename "$root_library")"
          cp "$output_dir/$(basename "$root_library")" "$output_dir/lib${name}.so"
          chmod u+w "$output_dir/lib${name}.so"
        done < <(
          find -L ${rootPackage} -type f -name '*.so' -print0 \
            | while IFS= read -r -d "" shared_library; do
                if file "$shared_library" | grep -q 'ARM aarch64'; then
                  printf '%s\n' "$shared_library"
                fi
              done
        )

        ${pkgs.lib.optionalString (manifestFile != null) ''
          if [ ! -f "${rootPackage}/${manifestFile}" ]; then
            echo "Expected FFI manifest ${manifestFile} was not produced" >&2
            exit 1
          fi
          cp "${rootPackage}/${manifestFile}" "$out/${manifestFile}"
        ''}
      '';
in
{
  buildHaskellLib =
    { ghcVersion
    , target ? "aarch64-android"
    , androidAbi ? "arm64-v8a"
    , packageFile
    , packageArgs ? { }
    , localPackages ? { }
    , name ? "haskell"
    , manifestFile ? null
    }:
    let
      thCross = th-cross.lib.${system}.mkCrossFor {
        inherit ghcVersion target;
      };
      rootPackage =
        thCross.buildPackage {
          inherit packageFile packageArgs localPackages;
          derivationArgs =
            pkgs.lib.optionalAttrs (manifestFile != null) {
              preConfigure = ''
                export HASKELL_FFI_MANIFEST="${placeholder "out"}/${manifestFile}"
                export HASKELL_FFI_LIBRARY_NAME="${name}"
                mkdir -p "$(dirname \"$HASKELL_FFI_MANIFEST\")"
              '';
            };
        };
    in
    copySharedLibraries {
      inherit name rootPackage androidAbi manifestFile;
      targetGhc = thCross.targetGhc;
    };
}
