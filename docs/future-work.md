# Future work

## Static-Haskell native linking follow-ups

Native Linux builds can now opt into `nativeLinkMode = "static-haskell"`, which
links Haskell package code and GHC boot-package code from `.dyn_o` archives into
one public shared library. Follow-up work remains:

- investigate whether non-glibc C dependencies can be linked from PIC static
  archives instead of copied into desktop bundles;
- decide whether RTS DWARF unwind and NUMA support should remain disabled
  unconditionally for `nativeLinkMode = "static-haskell"` or become explicit
  knobs;
- investigate symbol visibility, stripping, and linker garbage collection for
  reducing the size of the main FFI shared library;
- move the `.dyn_o` preservation strategy into `th-cross` for Android/cross-GHC
  builds;
- add automated ELF/linking tests for the static-Haskell mode.
