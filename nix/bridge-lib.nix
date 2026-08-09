{ pkgs
, th-cross
, system
, pruneUnusedNeeded ? pkgs.writeShellScriptBin "flutter-haskell-prune-unused-needed" ''
    exec ${pkgs.python3}/bin/python3 ${../tools/prune-unused-needed.py} "$@"
  ''
}:

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

  pruneUnusedNeededCommand = systemLibraries: ''
    ${pruneUnusedNeeded}/bin/flutter-haskell-prune-unused-needed \
      --library "$1" \
      --candidates "$candidates" \
      ${pkgs.lib.concatMapStringsSep " \\\n      " (libName: "--system-library ${pkgs.lib.escapeShellArg libName}") systemLibraries}
  '';

  systemLibraryPredicateScript = functionName: systemLibraries: ''
    ${functionName}() {
      case "$1" in
        ${pkgs.lib.concatMapStringsSep "|" (libName: "${libName}") systemLibraries})
          return 0
          ;;
        *)
          return 1
          ;;
      esac
    }
  '';

  copySharedLibraries =
    { name
    , rootPackage
    , targetGhc
    , androidAbi
    , manifestFile ? null
    , pruneUnusedDependencies ? true
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
          pkgs.binutils
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

        find_candidate() {
          awk -F '\t' -v name="$1" '$1 == name { print $2; exit }' "$candidates"
        }

        ${systemLibraryPredicateScript "is_android_system_library" androidSystemLibraries}

        prune_unused_needed() {
          ${pruneUnusedNeededCommand androidSystemLibraries}
        }

        copy_with_needed() {
          local source="$1"
          local prune_needed="''${2:-0}"
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
          ${pkgs.lib.optionalString pruneUnusedDependencies ''
          if [ "$prune_needed" = 1 ]; then
            prune_unused_needed "$destination"
          fi
          ''}

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
          copy_with_needed "$root_library" 1
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

  nativeGhcWithDynObjectArchives = ghcVersion:
    let
      haskellPackages = pkgs.haskell.packages.${ghcPackageSetName ghcVersion};
    in
    haskellPackages.ghc.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        dynObjectRoot="$out/lib/ghc-${ghcVersion}/dyn-o"
        mkdir -p "$dynObjectRoot"

        if [ -d _build ]; then
          find _build -type f -name '*.dyn_o' -print \
            | while IFS= read -r dyn_object; do
                install -Dm644 "$dyn_object" "$dynObjectRoot/$dyn_object"
              done
        fi

        find "$dynObjectRoot" -type f -name '*.dyn_o' | sort > "$dynObjectRoot/files"
      '';
    });

  nativeGhcDynObjectArchives =
    { ghcVersion
    , nativeGhc
    }:
    pkgs.runCommand "ghc-${ghcVersion}-dyn-object-archives"
      {
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.python3
        ];
      }
      ''
        set -euo pipefail

        dyn_object_root="${nativeGhc}/lib/ghc-${ghcVersion}/dyn-o"
        dyn_archive_dir="$out/lib/ghc-${ghcVersion}/dyn-archives"

        PYTHONPATH=${../tools} \
          ${pkgs.python3}/bin/python3 ${../tools/build-ghc-dyn-object-archives.py} \
          --ar ${pkgs.binutils}/bin/ar \
          --ranlib ${pkgs.binutils}/bin/ranlib \
          --ghc-pkg ${nativeGhc}/bin/ghc-pkg \
          --dyn-object-root "$dyn_object_root" \
          --out "$dyn_archive_dir"
      '';

  buildNativePackage =
    { ghcVersion
    , packageFile
    , packageArgs ? { }
    , localPackages ? { }
    , manifestFile ? null
    , name ? "haskell"
    , installDynObjectArchive ? false
    }:
    let
      haskellPackages = pkgs.haskell.packages.${ghcPackageSetName ghcVersion};
      withDynObjectArchive = package:
        if installDynObjectArchive then
          pkgs.haskell.lib.overrideCabal package (old: {
            postInstall = (old.postInstall or "") + ''
              dyn_archive_dir="$out/lib/ghc-dyn-o"
              mkdir -p "$dyn_archive_dir"

              dyn_objects="$(mktemp)"
              find . -type f -name '*.dyn_o' -print > "$dyn_objects"

              if [ -s "$dyn_objects" ]; then
                archive_source="$(
                  find "$out" -type f -name 'libHS*.a' ! -name '*_p.a' -print -quit
                )"
                if [ -z "$archive_source" ]; then
                  echo "Could not find installed Haskell archive for dyn_o package" >&2
                  exit 1
                fi

                archive="$dyn_archive_dir/$(basename "$archive_source")"
                xargs ar rcs "$archive" < "$dyn_objects"
                ranlib "$archive"
              fi
            '';
          })
        else
          package;
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
                withDynObjectArchive
                  (haskellPackages.callPackage
                    localPackage.packageFile
                    ((localPackage.packageArgs or { }) // localDependencyArguments)))
              localPackages);
      finalPackageArgs = packageArgs // localPackageOutputs;
      basePackage = withDynObjectArchive (haskellPackages.callPackage packageFile finalPackageArgs);
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

  linkNativeStaticHaskellLibrary =
    { name
    , rootPackage
    , nativeGhc
    , nativeGhcDynArchives
    , ghcVersion
    , manifestFile ? null
    }:
    let
      packageClosure = pkgs.closureInfo {
        rootPaths = [ rootPackage ];
      };
      libExt = sharedLibraryExtension;
    in
    pkgs.runCommand
      "${name}-${pkgs.stdenv.hostPlatform.system}-static-haskell-shared-lib"
      {
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.patchelf
          pkgs.python3
          pkgs.stdenv.cc
        ];
      }
      ''
        set -euo pipefail

        ${pkgs.lib.optionalString (!pkgs.stdenv.hostPlatform.isLinux) ''
          echo "nativeLinkMode = \"static-haskell\" is currently supported only on Linux" >&2
          exit 1
        ''}

        dyn_archive_dir="${nativeGhcDynArchives}/lib/ghc-${ghcVersion}/dyn-archives"

        PYTHONPATH=${../tools} \
          ${pkgs.python3}/bin/python3 ${../tools/link-static-haskell-native-lib.py} \
          --cc ${pkgs.stdenv.cc}/bin/cc \
          --patchelf ${pkgs.patchelf}/bin/patchelf \
          --ghc-pkg ${nativeGhc}/bin/ghc-pkg \
          --name ${pkgs.lib.escapeShellArg name} \
          --lib-extension ${pkgs.lib.escapeShellArg libExt} \
          --root-package ${rootPackage} \
          --store-paths ${packageClosure}/store-paths \
          --dyn-archive-dir "$dyn_archive_dir" \
          --out "$out" \
          ${pkgs.lib.optionalString (manifestFile != null) "--manifest-file ${pkgs.lib.escapeShellArg manifestFile}"}
      '';

  copyNativeSharedLibraries =
    { name
    , rootPackage
    , nativeGhc
    , manifestFile ? null
    , pruneUnusedDependencies ? true
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
            pkgs.binutils
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

          ${systemLibraryPredicateScript "is_linux_system_library" linuxSystemLibraries}

          prune_unused_needed() {
            ${pruneUnusedNeededCommand linuxSystemLibraries}
          }

          copy_with_needed() {
            local source="$1"
            local prune_needed="''${2:-0}"
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
            ${pkgs.lib.optionalString pruneUnusedDependencies ''
            if [ "$prune_needed" = 1 ]; then
              prune_unused_needed "$destination"
            fi
            ''}

            while IFS= read -r needed; do
              local needed_source
              needed_source="$(find_candidate "$needed")"
              if [ -n "$needed_source" ]; then
                copy_with_needed "$needed_source"
              fi
            done < <(patchelf --print-needed "$destination" 2>/dev/null || true)
          }

          copy_with_needed "$root_library" 1

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

        ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
          bridge_library_source="$output_dir/$(basename "$root_library")"
        ''}
        ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          bridge_library_source="$root_library"
        ''}
        cp "$bridge_library_source" "$output_dir/lib${name}${sharedLibraryExtension}"
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
    , pruneUnusedDependencies ? true
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
      inherit name rootPackage androidAbi manifestFile pruneUnusedDependencies;
      targetGhc = thCross.targetGhc;
    };

  buildNativeLib =
    { ghcVersion
    , packageFile
    , packageArgs ? { }
    , localPackages ? { }
    , name ? "haskell"
    , manifestFile ? null
    , pruneUnusedDependencies ? true
    , nativeLinkMode ? "dynamic"
    }:
    let
      haskellPackages = pkgs.haskell.packages.${ghcPackageSetName ghcVersion};
      staticHaskell = nativeLinkMode == "static-haskell";
      dynamic = nativeLinkMode == "dynamic";
      nativeGhc =
        if staticHaskell && !pkgs.stdenv.hostPlatform.isLinux then
          throw "nativeLinkMode = \"static-haskell\" is currently supported only on Linux"
        else if staticHaskell then
          nativeGhcWithDynObjectArchives ghcVersion
        else
          haskellPackages.ghc;
      nativeGhcDynArchives =
        pkgs.lib.optionalAttrs staticHaskell {
          nativeGhcDynArchives = nativeGhcDynObjectArchives {
            inherit ghcVersion nativeGhc;
          };
        };
      rootPackage =
        buildNativePackage {
          inherit ghcVersion packageFile packageArgs localPackages name manifestFile;
          installDynObjectArchive = staticHaskell;
        };
    in
    if dynamic then
      copyNativeSharedLibraries {
        inherit name rootPackage manifestFile pruneUnusedDependencies nativeGhc;
      }
    else if staticHaskell then
      linkNativeStaticHaskellLibrary ({
        inherit name rootPackage nativeGhc ghcVersion manifestFile;
      } // nativeGhcDynArchives)
    else
      throw "Unsupported nativeLinkMode: ${nativeLinkMode}";
}
