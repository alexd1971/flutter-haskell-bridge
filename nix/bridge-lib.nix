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

  linuxSystemLibraries = [
    "ld-linux-x86-64.so.2"
    "ld-linux-aarch64.so.1"
    "libanl.so.1"
    "libBrokenLocale.so.1"
    "libc.so.6"
    "libcrypt.so.1"
    "libdl.so.2"
    "libm.so.6"
    "libmvec.so.1"
    "libnsl.so.1"
    "libnss_compat.so.2"
    "libnss_dns.so.2"
    "libnss_files.so.2"
    "libpthread.so.0"
    "libresolv.so.2"
    "librt.so.1"
    "libthread_db.so.1"
    "libutil.so.1"
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

  sharedLibraryExtension =
    if pkgs.stdenv.hostPlatform.isDarwin then ".dylib" else ".so";

  ghcPackageSetName = ghcVersion:
    "ghc" + pkgs.lib.replaceStrings [ "." ] [ "" ] ghcVersion;

  buildNativePackage =
    { ghcVersion
    , packageFile
    , packageArgs ? { }
    , localPackages ? { }
    , manifestFile ? null
    , name ? "haskell"
    }:
    let
      haskellPackages = pkgs.haskell.packages.${ghcPackageSetName ghcVersion};
      localPackageOutputs =
        pkgs.lib.fix
          (self:
            pkgs.lib.mapAttrs
              (_: localPackage:
                let
                  packageArguments = builtins.functionArgs (import localPackage.packageFile);
                  localDependencyArguments =
                    pkgs.lib.filterAttrs
                      (packageName: _: builtins.hasAttr packageName packageArguments)
                      self;
                in
                haskellPackages.callPackage
                  localPackage.packageFile
                  ((localPackage.packageArgs or { }) // localDependencyArguments))
              localPackages);
      finalPackageArgs = packageArgs // localPackageOutputs;
      basePackage = haskellPackages.callPackage packageFile finalPackageArgs;
    in
    pkgs.haskell.lib.overrideCabal basePackage
      (old:
        pkgs.lib.optionalAttrs (manifestFile != null) {
          preBuild = (old.preBuild or "") + ''
            export HASKELL_FFI_MANIFEST="$TMPDIR/${manifestFile}"
            export HASKELL_FFI_LIBRARY_NAME="${name}"
            mkdir -p "$(dirname "$HASKELL_FFI_MANIFEST")"
          '';
          postInstall = (old.postInstall or "") + ''
            if [ ! -f "$TMPDIR/${manifestFile}" ]; then
              echo "Expected FFI manifest ${manifestFile} was not produced" >&2
              exit 1
            fi
            cp "$TMPDIR/${manifestFile}" "$out/${manifestFile}"
          '';
        });

  copyNativeSharedLibraries =
    { name
    , rootPackage
    , nativeGhc
    , manifestFile ? null
    }:
    let
      packageClosure = pkgs.closureInfo {
        # A Haskell shared library can leave RTS symbols unresolved. Include the
        # host RTS closure explicitly so its own dynamic dependencies are
        # available to the native bundle copier.
        rootPaths = [ rootPackage nativeGhc ];
      };
    in
    pkgs.runCommand
      "${name}-${pkgs.stdenv.hostPlatform.system}-shared-libs"
      {
        nativeBuildInputs =
          pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.patchelf
          ];
      }
      ''
        set -euo pipefail

        output_dir="$out/lib"
        mkdir -p "$output_dir"

        root_library="$(
          find ${rootPackage} -type f -name '*${sharedLibraryExtension}' -print -quit
        )"
        if [ -z "$root_library" ]; then
          echo "Could not find a native shared library in ${rootPackage}" >&2
          exit 1
        fi

        ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
          candidates="$(mktemp)"
          while IFS= read -r store_path; do
            find "$store_path" \( -type f -o -type l \) -name '*${sharedLibraryExtension}*' -print \
              | while IFS= read -r shared_library; do
                  printf '%s\t%s\n' "$(basename "$shared_library")" "$shared_library" >> "$candidates"
                done
          done < "${packageClosure}/store-paths"

          copied="$(mktemp)"

          find_candidate() {
            awk -F '\t' -v name="$1" '$1 == name { print $2; exit }' "$candidates"
          }

          is_linux_system_library() {
            case "$1" in
              ${pkgs.lib.concatMapStringsSep "|" (libName: "${libName}") linuxSystemLibraries})
                return 0
                ;;
              *)
                return 1
                ;;
            esac
          }

          copy_with_needed() {
            local source="$1"
            local soname
            soname="$(basename "$source")"

            if is_linux_system_library "$soname"; then
              return
            fi

            if grep -Fxq "$soname" "$copied"; then
              return
            fi
            printf '%s\n' "$soname" >> "$copied"

            local destination="$output_dir/$soname"
            cp "$source" "$destination"
            chmod u+w "$destination"
            patchelf --set-rpath '$ORIGIN' "$destination" 2>/dev/null || true

            while IFS= read -r needed; do
              local needed_source
              needed_source="$(find_candidate "$needed")"
              if [ -n "$needed_source" ]; then
                copy_with_needed "$needed_source"
              fi
            done < <(patchelf --print-needed "$destination" 2>/dev/null || true)
          }

          copy_with_needed "$root_library"

          native_rts="$(find -L ${nativeGhc} -type f -name 'libHSrts-*-ghc*.so' ! -name '*_debug*' ! -name '*_thr*' -print -quit)"
          if [ -z "$native_rts" ]; then
            echo "Could not find native GHC RTS in ${nativeGhc}" >&2
            exit 1
          fi
          copy_with_needed "$native_rts"

          if ! patchelf --print-needed "$output_dir/$(basename "$root_library")" \
              | grep -Fxq "$(basename "$native_rts")"; then
            patchelf --add-needed "$(basename "$native_rts")" "$output_dir/$(basename "$root_library")"
          fi
        ''}
        ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          while IFS= read -r store_path; do
            find "$store_path" -type f -name '*${sharedLibraryExtension}' -print \
              | while IFS= read -r shared_library; do
                  destination="$output_dir/$(basename "$shared_library")"
                  if [ ! -e "$destination" ]; then
                    cp "$shared_library" "$destination"
                    chmod u+w "$destination"
                  fi
                done
          done < "${packageClosure}/store-paths"
        ''}

        cp "$root_library" "$output_dir/lib${name}${sharedLibraryExtension}"
        chmod u+w "$output_dir/lib${name}${sharedLibraryExtension}"
        ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
          patchelf --set-rpath '$ORIGIN' "$output_dir/lib${name}${sharedLibraryExtension}" 2>/dev/null || true
          if [ -n "''${native_rts:-}" ] \
              && ! patchelf --print-needed "$output_dir/lib${name}${sharedLibraryExtension}" \
                | grep -Fxq "$(basename "$native_rts")"; then
            patchelf --add-needed "$(basename "$native_rts")" "$output_dir/lib${name}${sharedLibraryExtension}"
          fi
        ''}

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
  buildAndroidLib =
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
                mkdir -p "$(dirname "$HASKELL_FFI_MANIFEST")"
              '';
            };
        };
    in
    copySharedLibraries {
      inherit name rootPackage androidAbi manifestFile;
      targetGhc = thCross.targetGhc;
    };

  buildNativeLib =
    { ghcVersion
    , packageFile
    , packageArgs ? { }
    , localPackages ? { }
    , name ? "haskell"
    , manifestFile ? null
    }:
    let
      haskellPackages = pkgs.haskell.packages.${ghcPackageSetName ghcVersion};
      rootPackage =
        buildNativePackage {
          inherit ghcVersion packageFile packageArgs localPackages name manifestFile;
        };
    in
    copyNativeSharedLibraries {
      inherit name rootPackage manifestFile;
      nativeGhc = haskellPackages.ghc;
    };
}
