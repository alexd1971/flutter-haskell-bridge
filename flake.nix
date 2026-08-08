{
  description = "Flutter packaging helpers for Haskell libraries built with Template Haskell cross-compilation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    th-cross.url = "github:alexd1971/template-haskell-cross";
  };

  outputs = { self, nixpkgs, th-cross, ... }:
    let
      buildSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      importNixpkgs = buildSystem:
        import nixpkgs {
          system = buildSystem;
          # Android SDK/NDK packages contain unfree source archives whose
          # package names do not consistently share an `android-sdk-*` prefix.
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

      forEachBuildSystem = mkOutputs:
        nixpkgs.lib.foldl' nixpkgs.lib.recursiveUpdate { }
          (map
            (buildSystem:
              nixpkgs.lib.mapAttrs
                (_: sectionOutputs: { ${buildSystem} = sectionOutputs; })
                (mkOutputs (importNixpkgs buildSystem)))
            buildSystems);
    in
    forEachBuildSystem (pkgs:
      let
        tools = import ./nix/tools.nix { inherit pkgs; };
        bridgeLib = import ./nix/bridge-lib.nix {
          inherit pkgs th-cross;
          system = pkgs.stdenv.hostPlatform.system;
          pruneUnusedNeeded = tools.pruneUnusedNeeded;
        };
      in
      {
        packages = {
          dart-ffi-generator = tools.dartFfiGenerator;
          default = tools.dartFfiGenerator;
        };

        apps = {
          generate-dart-ffi-api = {
            type = "app";
            program = "${tools.dartFfiGenerator}/bin/flutter-haskell-generate-dart-ffi";
          };
        };

        lib = bridgeLib // {
          inherit tools;
        };
      })
    // {
      templates = {
        flutter-app = {
          path = ./templates/flutter-app;
          description = "Flutter app scaffold with an embedded Haskell bridge plugin";
        };

        flutter-plugin = {
          path = ./templates/flutter-plugin;
          description = "Flutter plugin scaffold backed by a cross-compiled Haskell FFI library";
        };

        default = self.templates.flutter-app;
      };
    };
}
