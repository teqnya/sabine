import 'package:flutter/material.dart';

void main() {
  runApp(const VeltrioApp());
}

/// Placeholder shell. The spike screen (model picker, JSON output, tok/s,
/// memory) lands once the llama.cpp binding is in place.
class VeltrioApp extends StatelessWidget {
  const VeltrioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veltrio',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('Veltrio — Phase 0 spike'))),
    );
  }
}
