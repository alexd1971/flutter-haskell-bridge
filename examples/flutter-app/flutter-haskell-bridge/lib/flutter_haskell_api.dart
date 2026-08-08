// Generated from the Haskell FFI manifest.
// Do not edit manually.

import 'dart:ffi' as ffi;
import 'dart:io' as io;

class HaskellApi {
  HaskellApi([String? libraryPath])
      : _library =
            ffi.DynamicLibrary.open(libraryPath ?? _defaultLibraryPath()) {
    _initializeRuntime();
  }

  static const libraryName = 'flutter_haskell_app';
  static const libraryFileName = 'libflutter_haskell_app.so';

  final ffi.DynamicLibrary _library;

  static String _defaultLibraryPath() {
    if (io.Platform.isLinux) {
      return '${io.File(io.Platform.resolvedExecutable).parent.path}/lib/$libraryFileName';
    }
    return libraryFileName;
  }

  late final _initializeRuntime = _library
      .lookupFunction<ffi.Void Function(), void Function()>('haskell_init');

  late final _addInt32 = _library.lookupFunction<
      ffi.Int32 Function(ffi.Int32, ffi.Int32),
      int Function(int, int)>('haskell_add_int32');

  int addInt32(int arg0, int arg1) {
    return _addInt32(arg0, arg1);
  }
}
