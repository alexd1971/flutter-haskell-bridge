import 'package:flutter/material.dart';
import 'package:bridge/bridge.dart';

void main() {
  runApp(const FlutterHaskellApp());
}

class FlutterHaskellApp extends StatelessWidget {
  const FlutterHaskellApp({super.key});

  @override
  Widget build(BuildContext context) {
    final result = HaskellApi().addInt32(20, 22);

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('20 + 22 from Haskell = $result'),
        ),
      ),
    );
  }
}
