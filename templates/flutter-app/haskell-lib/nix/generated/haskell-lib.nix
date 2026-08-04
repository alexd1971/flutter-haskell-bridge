{ base, lib, mkDerivation }:
mkDerivation {
  pname = "haskell-lib";
  version = "0.1.0.0";
  src = ../..;
  libraryHaskellDepends = [ base ];
  license = lib.meta.getLicenseFromSpdxId "BSD-3-Clause";
}
