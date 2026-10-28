import 'package:flutter/material.dart';

void main() {
  runApp(const SabineApp());
}

/// Placeholder shell. The spike screen (model picker, JSON output, tok/s,
/// memory) lands once the llama.cpp binding is in place.
class SabineApp extends StatelessWidget {
  const SabineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sabine',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('Sabine — Phase 0 spike'))),
    );
  }
}
