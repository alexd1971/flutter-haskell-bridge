# Future work

## Linux desktop shared-library bundles

The current bridge packaging path targets Android JNI libraries. Flutter desktop
support will need a similar bundling step for Linux shared libraries:

- copy the public Haskell shared library into the Flutter desktop bundle;
- recursively copy non-system `DT_NEEDED` dependencies from the Nix closure;
- rewrite bundled ELF RPATH/RUNPATH entries to `$ORIGIN`;
- create SONAME symlinks when a dependency records `libfoo.so.1` but the copied
  file is named `libfoo.so.1.2.3`.

The old `prototype-hs/hs-lib-ffi` experiment had a Python `bundle-elf.py` script
covering this shape. The implementation should be redone in this repository when
Flutter Linux desktop support becomes a real target.
