{
  # The FFI adapter is the root Haskell package built as the native bridge
  # library. It exports the C-callable symbols consumed from Dart.
  ffiAdapterPackage = {
    packageDir = "haskell-ffi";
    packageFile = ./haskell-ffi/nix/generated/haskell-ffi.nix;
  };

  # Haskell packages required by the FFI adapter that are not taken directly
  # from the selected package set. Attribute names must match Cabal dependency
  # names. Set `regenerate = false` for external packages with pre-generated
  # Nix expressions.
  ffiDependencyPackages = {
    haskell-lib = {
      packageDir = "haskell-lib";
      packageFile = ./haskell-lib/nix/generated/haskell-lib.nix;
    };
  };
}
