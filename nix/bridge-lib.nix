{ pkgs
, th-cross
, system
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
      { }
      ''
        set -euo pipefail

        PYTHONPATH=${../tools} \
          ${pkgs.python3}/bin/python3 ${../tools/bundle-android-dynamic-libs.py} \
          --file ${pkgs.file}/bin/file \
          --nm ${pkgs.binutils}/bin/nm \
          --patchelf ${pkgs.patchelf}/bin/patchelf \
          --name ${pkgs.lib.escapeShellArg name} \
          --android-abi ${pkgs.lib.escapeShellArg androidAbi} \
          --root-package ${rootPackage} \
          --target-ghc ${targetGhc} \
          --store-paths ${packageClosure}/store-paths \
          --out "$out" \
          --candidate-file-substring ${pkgs.lib.escapeShellArg "ARM aarch64"} \
          ${pkgs.lib.optionalString pruneUnusedDependencies "--prune-unused-needed"} \
          ${pkgs.lib.optionalString (manifestFile != null) "--manifest-file ${pkgs.lib.escapeShellArg manifestFile}"} \
          ${pkgs.lib.concatMapStringsSep " \\\n          " (libName: "--system-library ${pkgs.lib.escapeShellArg libName}") androidSystemLibraries}
      '';

  sharedLibraryExtension =
    if pkgs.stdenv.hostPlatform.isDarwin then ".dylib" else ".so";

  ghcPackageSetName = ghcVersion:
    "ghc" + pkgs.lib.replaceStrings [ "." ] [ "" ] ghcVersion;

  androidCrossPkgsFor = target:
    if target == "aarch64-android" then
      pkgs.pkgsCross.aarch64-android-prebuilt
    else
      throw "Unsupported Android static-Haskell target: ${target}";

  installDynObjectArchiveHook = { ar, ranlib }: ''
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
      ${ar} rcs "$archive" @"$dyn_objects"
      ${ranlib} "$archive"
    fi
  '';

  nativeGhcWithDynObjectArchives = ghcVersion:
    let
      haskellPackages = pkgs.haskell.packages.${ghcPackageSetName ghcVersion};
    in
    (haskellPackages.ghc.override {
      enableDwarf = false;
      enableNuma = false;
    }).overrideAttrs (old: {
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
              ${installDynObjectArchiveHook {
                ar = "${pkgs.binutils}/bin/ar";
                ranlib = "${pkgs.binutils}/bin/ranlib";
              }}
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
        rootPaths = [ rootPackage nativeGhc ];
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
          --output-subdir lib \
          --root-package ${rootPackage} \
          --store-paths ${packageClosure}/store-paths \
          --dyn-archive-dir "$dyn_archive_dir" \
          --out "$out" \
          ${pkgs.lib.concatMapStringsSep " \\\n          " (libName: "--system-library ${pkgs.lib.escapeShellArg libName}") linuxSystemLibraries} \
          ${pkgs.lib.optionalString (manifestFile != null) "--manifest-file ${pkgs.lib.escapeShellArg manifestFile}"}
      '';

  buildAndroidPackage =
    { thCross
    , target
    , packageFile
    , packageArgs ? { }
    , localPackages ? { }
    , manifestFile ? null
    , name ? "haskell"
    , installDynObjectArchive ? false
    }:
    let
      crossPkgs = androidCrossPkgsFor target;
      targetArchiveHook = old: {
        postInstall = (old.postInstall or "") + ''
          ${installDynObjectArchiveHook {
            ar = "${crossPkgs.stdenv.cc.bintools.bintools}/bin/${crossPkgs.stdenv.cc.bintools.targetPrefix}ar";
            ranlib = "${crossPkgs.stdenv.cc.bintools.bintools}/bin/${crossPkgs.stdenv.cc.bintools.targetPrefix}ranlib";
          }}
        '';
      };
      localPackagesWithDynObjectArchives =
        if installDynObjectArchive then
          pkgs.lib.mapAttrs
            (_: localPackage:
              localPackage // {
                derivationArgs = old:
                  (if builtins.hasAttr "derivationArgs" localPackage then
                    localPackage.derivationArgs old
                  else
                    { })
                  // (targetArchiveHook old);
              })
            localPackages
        else
          localPackages;
    in
    thCross.buildPackage {
      inherit packageFile packageArgs;
      localPackages = localPackagesWithDynObjectArchives;
      derivationArgs =
        (pkgs.lib.optionalAttrs (manifestFile != null) {
          preConfigure = ''
            export HASKELL_FFI_MANIFEST="${placeholder "out"}/${manifestFile}"
            export HASKELL_FFI_LIBRARY_NAME="${name}"
            mkdir -p "$(dirname "$HASKELL_FFI_MANIFEST")"
          '';
        })
        // (pkgs.lib.optionalAttrs installDynObjectArchive {
          postInstall = (targetArchiveHook { }).postInstall;
        });
    };

  linkAndroidStaticHaskellLibrary =
    { name
    , rootPackage
    , targetGhc
    , targetGhcDynArchives
    , ghcVersion
    , androidAbi
    , target
    , manifestFile ? null
    }:
    let
      packageClosure = pkgs.closureInfo {
        rootPaths = [ rootPackage targetGhc ];
      };
      crossPkgs = androidCrossPkgsFor target;
    in
    pkgs.runCommand
      "${name}-${androidAbi}-static-haskell-jni-lib"
      {
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.file
          pkgs.patchelf
          pkgs.python3
        ];
      }
      ''
        set -euo pipefail

        ${pkgs.lib.optionalString (androidAbi != "arm64-v8a") ''
          echo "androidLinkMode = \"static-haskell\" is currently supported only for arm64-v8a" >&2
          exit 1
        ''}

        dyn_archive_dir="${targetGhcDynArchives}/lib/ghc-${ghcVersion}/dyn-archives"

        PYTHONPATH=${../tools} \
          ${pkgs.python3}/bin/python3 ${../tools/link-static-haskell-native-lib.py} \
          --cc ${crossPkgs.stdenv.cc}/bin/${crossPkgs.stdenv.cc.targetPrefix}cc \
          --patchelf ${pkgs.patchelf}/bin/patchelf \
          --file ${pkgs.file}/bin/file \
          --ghc-pkg ${targetGhc}/bin/${crossPkgs.stdenv.cc.targetPrefix}ghc-pkg \
          --name ${pkgs.lib.escapeShellArg name} \
          --lib-extension .so \
          --candidate-file-substring "ARM aarch64" \
          --output-subdir ${pkgs.lib.escapeShellArg androidAbi} \
          --root-package ${rootPackage} \
          --store-paths ${packageClosure}/store-paths \
          --dyn-archive-dir "$dyn_archive_dir" \
          --out "$out" \
          ${pkgs.lib.concatMapStringsSep " \\\n          " (libName: "--system-library ${pkgs.lib.escapeShellArg libName}") androidSystemLibraries} \
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
      { }
      ''
        set -euo pipefail

        PYTHONPATH=${../tools} \
          ${pkgs.python3}/bin/python3 ${../tools/bundle-native-dynamic-libs.py} \
          --platform ${
            if pkgs.stdenv.hostPlatform.isDarwin then
              "darwin"
            else if pkgs.stdenv.hostPlatform.isLinux then
              "linux"
            else
              throw "Unsupported native Flutter desktop system: ${pkgs.stdenv.hostPlatform.system}"
          } \
          --name ${pkgs.lib.escapeShellArg name} \
          --lib-extension ${pkgs.lib.escapeShellArg sharedLibraryExtension} \
          --root-package ${rootPackage} \
          --native-ghc ${nativeGhc} \
          --store-paths ${packageClosure}/store-paths \
          --out "$out" \
          ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux "--nm ${pkgs.binutils}/bin/nm"} \
          ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux "--patchelf ${pkgs.patchelf}/bin/patchelf"} \
          ${pkgs.lib.optionalString pruneUnusedDependencies "--prune-unused-needed"} \
          ${pkgs.lib.optionalString (manifestFile != null) "--manifest-file ${pkgs.lib.escapeShellArg manifestFile}"} \
          ${pkgs.lib.concatMapStringsSep " \\\n          " (libName: "--system-library ${pkgs.lib.escapeShellArg libName}") linuxSystemLibraries}
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
    , androidLinkMode ? "dynamic"
    }:
    let
      staticHaskell = androidLinkMode == "static-haskell";
      dynamic = androidLinkMode == "dynamic";
      thCross = th-cross.lib.${system}.mkCrossFor {
        inherit ghcVersion target;
      };
      rootPackage =
        buildAndroidPackage {
          inherit thCross target packageFile packageArgs localPackages name manifestFile;
          installDynObjectArchive = staticHaskell;
        };
    in
    if dynamic then
      copySharedLibraries {
        inherit name rootPackage androidAbi manifestFile pruneUnusedDependencies;
        targetGhc = thCross.targetGhc;
      }
    else if staticHaskell then
      linkAndroidStaticHaskellLibrary {
        inherit name rootPackage ghcVersion androidAbi target manifestFile;
        targetGhc = thCross.targetGhc;
        targetGhcDynArchives = thCross.targetGhcDynObjectArchives;
      }
    else
      throw "Unsupported androidLinkMode: ${androidLinkMode}";

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
