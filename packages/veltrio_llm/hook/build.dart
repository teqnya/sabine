import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Bundles the prebuilt libveltrio_llm.dylib produced by
/// `scripts/build_native.sh`. Nothing is downloaded at build time.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;

    final String? target = switch (code.targetOS) {
      OS.iOS
          when code.iOS.targetSdk == IOSSdk.iPhoneOS &&
              code.targetArchitecture == Architecture.arm64 =>
        'ios-arm64',
      OS.macOS => 'macos-${_archDir(code.targetArchitecture)}',
      _ => null,
    };
    // Unsupported targets (simulator, Android for now) get no library; the
    // Dart side reports that clearly at load time.
    if (target == null) return;

    final lib = input.packageRoot.resolve(
      'native/$target/libveltrio_llm.dylib',
    );
    if (!File.fromUri(lib).existsSync()) {
      // A missing iPhone library makes the app useless, so fail the build.
      // On macOS (host tests) tests skip instead.
      if (code.targetOS == OS.iOS) {
        throw StateError(
          'Missing native/$target/libveltrio_llm.dylib. '
          'Run packages/veltrio_llm/scripts/build_native.sh ios',
        );
      }
      return;
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'veltrio_llm.dart',
        linkMode: DynamicLoadingBundled(),
        file: lib,
      ),
    );
    output.dependencies.add(lib);
  });
}

String _archDir(Architecture arch) => switch (arch) {
  Architecture.x64 => 'x86_64',
  Architecture.arm64 => 'arm64',
  _ => arch.name,
};
