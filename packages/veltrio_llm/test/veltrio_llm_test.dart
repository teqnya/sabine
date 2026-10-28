import 'dart:io';

import 'package:test/test.dart';
import 'package:veltrio_llm/veltrio_llm.dart';

/// Native smoke tests. They need the host library
/// (`scripts/build_native.sh macos`); the generation test also needs a GGUF
/// model path in VELTRIO_TEST_MODEL.
void main() {
  final available = LlamaModel.isAvailable;
  final modelPath = Platform.environment['VELTRIO_TEST_MODEL'];

  test(
    'reports memory footprint',
    () => expect(LlamaModel.memoryFootprint(), greaterThan(0)),
    skip: available ? false : 'native library not built for this host',
  );

  test(
    'rejects a missing model file',
    () => expect(
      () => LlamaModel.load('/nonexistent/model.gguf'),
      throwsA(isA<LlamaException>()),
    ),
    skip: available ? false : 'native library not built for this host',
  );

  test(
    'generates grammar-constrained JSON',
    () {
      final model = LlamaModel.load(modelPath!, gpuLayers: 0);
      addTearDown(model.dispose);
      final r = model.generate(
        user: 'Classify: "Server down, production stopped". Reply as JSON.',
        grammar: r'root ::= "{\"category\": \"" ("urgent" | "fyi") "\"}"',
        maxTokens: 32,
      );
      expect(r.text, anyOf('{"category": "urgent"}', '{"category": "fyi"}'));
      expect(r.generatedTokens, greaterThan(0));
      expect(r.promptTokens, greaterThan(0));
    },
    skip: !available
        ? 'native library not built for this host'
        : modelPath == null
        ? 'set VELTRIO_TEST_MODEL to a .gguf path'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'prefix cache reuse gives the same output as a fresh context',
    () {
      const prefix =
          'You are a careful assistant. Classify the email below as urgent '
          'or fyi and answer with one word.\n\nEmail: ';
      const first = '${prefix}Lunch menu for Friday is attached.';
      const second = '${prefix}The production line is down since 7am.';

      final warm = LlamaModel.load(modelPath!, gpuLayers: 0);
      addTearDown(warm.dispose);
      warm.generate(user: first, maxTokens: 8);
      final reused = warm.generate(user: second, maxTokens: 8);

      final fresh = LlamaModel.load(modelPath, gpuLayers: 0);
      addTearDown(fresh.dispose);
      final clean = fresh.generate(user: second, maxTokens: 8);

      expect(reused.cachedTokens, greaterThan(10));
      expect(clean.cachedTokens, 0);
      expect(reused.text, clean.text);

      // Same prompt again: everything but the last token is reused.
      final again = warm.generate(user: second, maxTokens: 8);
      expect(again.cachedTokens, again.promptTokens - 1);
      expect(again.text, clean.text);
    },
    skip: !available
        ? 'native library not built for this host'
        : modelPath == null
        ? 'set VELTRIO_TEST_MODEL to a .gguf path'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
