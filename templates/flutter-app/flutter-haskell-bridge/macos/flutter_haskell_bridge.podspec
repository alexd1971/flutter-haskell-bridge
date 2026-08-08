Pod::Spec.new do |s|
  s.name             = 'flutter_haskell_bridge'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin that bridges Dart and a local Haskell FFI library.'
  s.description      = 'Flutter plugin that bridges Dart and a local Haskell FFI library.'
  s.homepage         = 'https://github.com/alexd1971/flutter-haskell-bridge'
  s.license          = { :type => 'BSD-3-Clause' }
  s.author           = { 'flutter-haskell-bridge' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.vendored_libraries = 'lib/*.dylib'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
