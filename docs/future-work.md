# Future work

## Static-Haskell native linking follow-ups

Native Linux builds can now opt into `nativeLinkMode = "static-haskell"`, which
links Haskell package code and GHC boot-package code from `.dyn_o` archives into
one public shared library. Follow-up work remains:

- reduce or make configurable RTS C-library dependencies such as `libdw` and
  `libnuma`;
- investigate whether non-glibc C dependencies can be linked from PIC static
  archives instead of copied into desktop bundles;
- move the `.dyn_o` preservation strategy into `th-cross` for Android/cross-GHC
  builds;
- add automated ELF/linking tests for the static-Haskell mode.
