{ mkDerivation, base, haskell-ffi-th, haskell-lib, lib
, template-haskell
}:
mkDerivation {
  pname = "haskell-ffi";
  version = "0.1.0.0";
  src = ../..;
  libraryHaskellDepends = [
    base haskell-ffi-th haskell-lib template-haskell
  ];
  license = lib.meta.getLicenseFromSpdxId "BSD-3-Clause";
}
