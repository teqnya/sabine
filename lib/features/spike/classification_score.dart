import '../../core/ai/triage.dart';

/// One model prediction; [predicted] is null when the output failed to parse.
class Prediction {
  const Prediction({
    required this.id,
    required this.language,
    required this.expected,
    required this.predicted,
  });

  final String id;
  final String language;
  final TriageCategory expected;
  final TriageCategory? predicted;

  bool get correct => predicted == expected;
}

/// Agreement with owner labels. Parse failures count as wrong, never skipped.
class ClassificationScore {
  ClassificationScore(this.predictions);

  /// CLAUDE.md §3 success criterion.
  static const targetAccuracy = 0.85;

  final List<Prediction> predictions;

  int get total => predictions.length;
  int get correct => predictions.where((p) => p.correct).length;
  int get parseFailures => predictions.where((p) => p.predicted == null).length;

  double get accuracy => total == 0 ? 0 : correct / total;
  bool get meetsTarget => accuracy >= targetAccuracy;

  Map<String, double> get accuracyByLanguage {
    final byLang = <String, List<Prediction>>{};
    for (final p in predictions) {
      byLang.putIfAbsent(p.language, () => []).add(p);
    }
    return byLang.map(
      (lang, ps) =>
          MapEntry(lang, ps.where((p) => p.correct).length / ps.length),
    );
  }

  /// confusion[expected][predicted]; a null predicted key means parse failure.
  Map<TriageCategory, Map<TriageCategory?, int>> get confusion {
    final matrix = <TriageCategory, Map<TriageCategory?, int>>{};
    for (final p in predictions) {
      final row = matrix.putIfAbsent(p.expected, () => {});
      row[p.predicted] = (row[p.predicted] ?? 0) + 1;
    }
    return matrix;
  }
}
