import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final assetDir = _assetDirectory(input);
    if (assetDir == null || !assetDir.existsSync()) {
      return;
    }

    final libraries =
        assetDir
            .listSync()
            .whereType<File>()
            .where((file) => _isNativeLibrary(file.path))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final library in libraries) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: library.uri.pathSegments.last,
          linkMode: DynamicLoadingBundled(),
          file: library.absolute.uri,
        ),
      );
    }
  });
}

Directory? _assetDirectory(HookInput input) {
  final root = Directory.fromUri(input.packageRoot);
  final os = input.config.code.targetOS;
  final architecture = input.config.code.targetArchitecture;

  if (os == OS.android) {
    return Directory.fromUri(
      root.uri.resolve('native_assets/android/${_androidAbi(architecture)}/'),
    );
  }
  if (os == OS.linux) {
    return Directory.fromUri(root.uri.resolve('native_assets/linux/'));
  }
  if (os == OS.macOS) {
    return Directory.fromUri(root.uri.resolve('native_assets/macos/'));
  }

  return null;
}

String _androidAbi(Architecture architecture) {
  if (architecture == Architecture.arm64) {
    return 'arm64-v8a';
  }
  if (architecture == Architecture.arm) {
    return 'armeabi-v7a';
  }
  if (architecture == Architecture.x64) {
    return 'x86_64';
  }
  if (architecture == Architecture.ia32) {
    return 'x86';
  }
  throw UnsupportedError('Unsupported Android architecture: $architecture');
}

bool _isNativeLibrary(String path) {
  return path.endsWith('.dylib') ||
      path.endsWith('.so') ||
      path.contains('.so.');
}
