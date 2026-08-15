# Runtime Initialization

Dart loads a cross-compiled Haskell shared library through `dart:ffi`
`DynamicLibrary.open`. Unlike a normal executable linked against the Haskell
RTS, a `dlopen`'d library does not run RTS startup code on its own. The
generated Dart API class therefore calls a `haskell_init` symbol in its
constructor before invoking any `foreign export`:

```dart
class HaskellApi {
  HaskellApi([String? libraryPath])
      : _library = ffi.DynamicLibrary.open(libraryPath ?? _defaultLibraryPath()) {
    _initializeRuntime();
  }

  late final _initializeRuntime = _library
      .lookupFunction<ffi.Void Function(), void Function()>('haskell_init');
  ...
}
```

The `runtimeInitSymbol` field of the FFI manifest defaults to `haskell_init`
(see `tools/generate-dart-ffi-api.py`).

## Consumer Contract

Each consumer package owns a `cbits/haskell_runtime.c` shim that calls
`hs_init` and declares it via `c-sources` in the `.cabal` file. The templates
(`templates/flutter-app/`, `templates/flutter-ffi-package/`) ship this file out of
the box; consumers created from a template do not need to add anything.

A hand-built consumer that omits the shim will crash at runtime with
`undefined symbol: haskell_init` on the first FFI call. The fix is to copy
`cbits/haskell_runtime.c` from a template and add
`c-sources: cbits/haskell_runtime.c` to the library stanza.

## Idempotency

The shim uses `pthread_once` so `hs_init` runs exactly once per process even
when multiple Haskell libraries are loaded or `HaskellApi` is instantiated
multiple times.

## Shutdown

The shim intentionally does not expose `haskell_exit`. Haskell shared libraries
loaded by a long-lived Flutter process never shut the RTS down explicitly; the
process exit reclaims resources.
