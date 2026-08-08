# Future work

## Fully static Haskell payloads

The current bridge builders still bundle GHC runtime/base shared libraries and
non-system dynamic dependencies required by those libraries. They do prune
unused direct `DT_NEEDED` entries from the root FFI library, which removes
Template Haskell build-time packages from runtime bundles in typical projects.

A stronger optimization would produce one public shared library that statically
contains the project Haskell code and leaves only platform/system dynamic
dependencies. The straightforward approach is currently blocked by Cabal/GHC
installing non-PIC vanilla static archives; the generated `.dyn_o` objects are
not installed as a ready-to-link archive. Solving this likely requires a deeper
package build strategy for PIC static archives or an explicit dynamic-object
archive/link step.
