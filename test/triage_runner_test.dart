import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sabine/core/ai/local_llm.dart';
import 'package:sabine/core/ai/triage.dart';
import 'package:sabine/features/spike/test_dataset.dart';
import 'package:sabine/features/spike/triage_runner.dart';

/// Replies from a script keyed by a substring of the prompt.
class _FakeLlm implements LocalLlm {
  _FakeLlm(this.replies);

  final Map<String, Object> replies;
  final prompts = <LlmRequest>[];

  @override
  Future<LlmResult> generate(LlmRequest request) async {
    prompts.add(request);
    final reply = replies.entries
        .firstWhere((e) => request.prompt.contains(e.key))
        .value;
    if (reply is LlmException) throw reply;
    return LlmResult(
      text: reply as String,
      promptTokens: 100,
      generatedTokens: 10,
      promptEvalTime: const Duration(milliseconds: 200),
      generationTime: const Duration(milliseconds: 500),
      peakMemoryBytes: 1000,
    );
  }

  @override
  Future<ModelInfo> load(LlmLoadConfig config) => throw UnimplementedError();

  @override
  Future<void> unload() async {}
}

TestMessage _msg(String id, {String body = 'body'}) => TestMessage(
  id: id,
  language: 'en',
  from: 'a@example.com',
  subject: 'Subject $id',
  date: '2026-10-28',
  body: body,
);

void main() {
  final prompt = TriagePrompt(
    template: File('lib/core/ai/prompts/triage.v1.txt').readAsStringSync(),
    grammar: File('lib/core/ai/schemas/triage.v1.gbnf').readAsStringSync(),
  );

  test('grammar covers every category', () {
    for (final c in TriageCategory.values) {
      expect(prompt.grammar, contains('"\\"${c.wire}\\""'));
    }
  });

  test('clips long bodies and flags them', () {
    final (text, clipped) = prompt.render(
      _msg('x', body: 'a' * (maxBodyChars + 50)),
    );
    expect(clipped, isTrue);
    expect(text, isNot(contains('a' * (maxBodyChars + 1))));
  });

  test(
    'batch scores correct, wrong, unparseable and failed messages',
    () async {
      final ds = TestDataset(
        [_msg('m1'), _msg('m2'), _msg('m3'), _msg('m4')],
        {
          for (final id in ['m1', 'm2', 'm3', 'm4'])
            id: TestLabel(id: id, category: TriageCategory.urgent),
        },
      );
      final llm = _FakeLlm({
        'Subject m1': '{"category":"urgent","summary":"ok"}',
        'Subject m2': '{"category":"fyi","summary":"wrong"}',
        'Subject m3': 'not json',
        'Subject m4': LlmException('prompt too long'),
      });
      final progress = <int>[];

      final report = await runBatch(
        llm,
        prompt,
        ds,
        onProgress: (d, _) => progress.add(d),
      );

      expect(progress, [1, 2, 3, 4]);
      expect(llm.prompts.every((r) => r.grammar == prompt.grammar), isTrue);
      expect(report.score.correct, 1);
      expect(report.score.parseFailures, 2);
      expect(report.errors, 2);
      expect(report.runs[3].error, 'prompt too long');
      expect(report.runs[2].raw, 'not json');
      expect(report.averageTokensPerSecond, closeTo(20, 0.001));
      expect(report.peakMemoryBytes, 1000);
    },
  );

  test('batch stops when cancelled', () async {
    final ds = TestDataset(
      [_msg('m1'), _msg('m2')],
      {
        for (final id in ['m1', 'm2'])
          id: TestLabel(id: id, category: TriageCategory.fyi),
      },
    );
    final llm = _FakeLlm({'Subject': '{"category":"fyi","summary":"s"}'});
    var cancel = false;
    final report = await runBatch(
      llm,
      prompt,
      ds,
      onProgress: (_, _) => cancel = true,
      isCancelled: () => cancel,
    );
    expect(report.runs, hasLength(1));
  });
}
