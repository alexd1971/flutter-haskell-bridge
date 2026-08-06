# Changes

## Unreleased

### RTS initialization contract documented

Documented the runtime initialization contract: each consumer package owns a
`cbits/haskell_runtime.c` shim (calling `hs_init` via `pthread_once`) and
declares it via `c-sources` in the `.cabal` file. The templates already ship
this file out of the box. See `docs/runtime-auto-init.md`.
