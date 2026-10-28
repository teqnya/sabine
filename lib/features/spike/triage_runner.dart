import '../../core/ai/local_llm.dart';
import '../../core/ai/triage.dart';
import 'classification_score.dart';
import 'test_dataset.dart';

/// Long bodies are clipped so one message fits the small context (CLAUDE.md §6).
/// Thread chunking comes with the summary task.
const maxBodyChars = 3000;

class TriagePrompt {
  const TriagePrompt({required this.template, required this.grammar});

  /// `prompts/triage.v1.txt`
  final String template;

  /// `schemas/triage.v1.gbnf`
  final String grammar;

  /// Renders the prompt for [m]; returns it and whether the body was clipped.
  (String, bool) render(TestMessage m) {
    final clipped = m.body.length > maxBodyChars;
    final body = clipped ? m.body.substring(0, maxBodyChars) : m.body;
    return (
      renderPrompt(template, {
        'from': m.from,
        'subject': m.subject,
        'date': m.date,
        'body': body,
      }),
      clipped,
    );
  }
}

class TriageRun {
  const TriageRun({
    required this.message,
    required this.label,
    required this.truncated,
    this.raw,
    this.result,
    this.error,
    this.stats,
  });

  final TestMessage message;
  final TestLabel label;
  final bool truncated;

  /// Model output; null if generation itself failed.
  final String? raw;
  final TriageResult? result;

  /// Generation or parse error, shown as-is in the UI (CLAUDE.md §2.7).
  final String? error;
  final LlmResult? stats;

  bool get correct => result?.category == label.category;

  Prediction toPrediction() => Prediction(
    id: message.id,
    language: message.language,
    expected: label.category,
    predicted: result?.category,
  );
}

Future<TriageRun> runTriage(
  LocalLlm llm,
  TriagePrompt prompt,
  TestMessage message,
  TestLabel label,
) async {
  final (text, truncated) = prompt.render(message);
  final LlmResult stats;
  try {
    stats = await llm.generate(
      LlmRequest(prompt: text, grammar: prompt.grammar, maxTokens: 128),
    );
  } on LlmException catch (e) {
    return TriageRun(
      message: message,
      label: label,
      truncated: truncated,
      error: e.message,
    );
  }
  try {
    return TriageRun(
      message: message,
      label: label,
      truncated: truncated,
      raw: stats.text,
      result: parseTriage(stats.text),
      stats: stats,
    );
  } on TriageParseException catch (e) {
    return TriageRun(
      message: message,
      label: label,
      truncated: truncated,
      raw: stats.text,
      error: e.message,
      stats: stats,
    );
  }
}

class BatchReport {
  BatchReport(this.runs, this.wallTime);

  final List<TriageRun> runs;
  final Duration wallTime;

  ClassificationScore get score =>
      ClassificationScore(runs.map((r) => r.toPrediction()).toList());

  Iterable<LlmResult> get _stats => runs.map((r) => r.stats).nonNulls;

  Duration get averagePerMessage => runs.isEmpty
      ? Duration.zero
      : Duration(microseconds: wallTime.inMicroseconds ~/ runs.length);

  /// Mean generation speed over messages that produced tokens.
  double get averageTokensPerSecond {
    final speeds = _stats
        .where((s) => s.generatedTokens > 0)
        .map((s) => s.generationTokensPerSecond)
        .toList();
    return speeds.isEmpty ? 0 : speeds.reduce((a, b) => a + b) / speeds.length;
  }

  int? get peakMemoryBytes {
    final peaks = _stats.map((s) => s.peakMemoryBytes).nonNulls;
    return peaks.isEmpty ? null : peaks.reduce((a, b) => a > b ? a : b);
  }

  int get errors => runs.where((r) => r.error != null).length;
}

/// Runs every message in order, one at a time. [isCancelled] is checked
/// between messages; a cancelled batch reports the messages done so far.
Future<BatchReport> runBatch(
  LocalLlm llm,
  TriagePrompt prompt,
  TestDataset dataset, {
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final sw = Stopwatch()..start();
  final runs = <TriageRun>[];
  for (final m in dataset.messages) {
    if (isCancelled?.call() ?? false) break;
    runs.add(await runTriage(llm, prompt, m, dataset.labels[m.id]!));
    onProgress?.call(runs.length, dataset.messages.length);
  }
  return BatchReport(runs, sw.elapsed);
}
