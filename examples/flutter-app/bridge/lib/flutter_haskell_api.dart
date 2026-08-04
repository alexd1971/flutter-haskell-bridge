// Generated from the Haskell FFI manifest.
// Do not edit manually.

import 'dart:ffi' as ffi;

class HaskellApi {
  HaskellApi([String libraryPath = 'libflutter_haskell_app.so'])
      : _library = ffi.DynamicLibrary.open(libraryPath) {
    _initializeRuntime();
  }

  static const libraryName = 'flutter_haskell_app';

  final ffi.DynamicLibrary _library;

  late final _initializeRuntime = _library
      .lookupFunction<ffi.Void Function(), void Function()>('haskell_init');

  late final _addInt32 = _library
      .lookupFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32), int Function(int, int)>('haskell_add_int32');

  int addInt32(int arg0, int arg1) {
    return _addInt32(arg0, arg1);
  }
}
