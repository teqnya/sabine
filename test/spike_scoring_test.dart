import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sabine/core/ai/triage.dart';
import 'package:sabine/features/spike/classification_score.dart';
import 'package:sabine/features/spike/test_dataset.dart';

void main() {
  test('committed test data is consistent', () {
    final ds = TestDataset.parse(
      File('spike/testdata/messages.json').readAsStringSync(),
      File('spike/testdata/labels.json').readAsStringSync(),
    );
    expect(ds.messages, isNotEmpty);
    expect(
      ds.messages.map((m) => m.language).toSet(),
      everyElement(isIn(['de', 'en', 'ar'])),
    );
  });

  test('rejects unlabeled messages', () {
    const messages =
        '[{"id":"a","language":"en","from":"x","subject":"s","date":"d","body":"b"}]';
    expect(() => TestDataset.parse(messages, '[]'), throwsFormatException);
  });

  test('rejects unknown label category', () {
    const messages =
        '[{"id":"a","language":"en","from":"x","subject":"s","date":"d","body":"b"}]';
    expect(
      () => TestDataset.parse(messages, '[{"id":"a","category":"spam"}]'),
      throwsFormatException,
    );
  });

  group('ClassificationScore', () {
    Prediction p(String lang, TriageCategory exp, TriageCategory? pred) =>
        Prediction(id: 'x', language: lang, expected: exp, predicted: pred);

    test('counts parse failures as wrong', () {
      final s = ClassificationScore([
        p('de', TriageCategory.urgent, TriageCategory.urgent),
        p('de', TriageCategory.fyi, null),
        p('en', TriageCategory.noise, TriageCategory.noise),
        p('en', TriageCategory.noise, TriageCategory.fyi),
      ]);
      expect(s.accuracy, 0.5);
      expect(s.parseFailures, 1);
      expect(s.meetsTarget, isFalse);
      expect(s.accuracyByLanguage, {'de': 0.5, 'en': 0.5});
      expect(s.confusion[TriageCategory.fyi], {null: 1});
      expect(s.confusion[TriageCategory.noise], {
        TriageCategory.noise: 1,
        TriageCategory.fyi: 1,
      });
    });

    test('meets target at 85%', () {
      final s = ClassificationScore([
        for (var i = 0; i < 17; i++)
          p('en', TriageCategory.fyi, TriageCategory.fyi),
        for (var i = 0; i < 3; i++)
          p('en', TriageCategory.fyi, TriageCategory.noise),
      ]);
      expect(s.accuracy, 0.85);
      expect(s.meetsTarget, isTrue);
    });
  });
}
