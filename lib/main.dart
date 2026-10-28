import 'package:flutter/material.dart';

import 'features/spike/spike_screen.dart';

void main() {
  runApp(const VeltrioApp());
}

class VeltrioApp extends StatelessWidget {
  const VeltrioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veltrio',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const SpikeScreen(),
    );
  }
}
