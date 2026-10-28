import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sabine/core/ai/triage.dart';
import 'package:sabine/features/spike/test_dataset.dart';
import 'package:sabine/features/triage/noise_rules.dart';

void main() {
  String? match(String from, {String subject = 's', String body = 'b'}) =>
      matchNoiseRule(from: from, subject: subject, body: body);

  test('bulk sender mailboxes are noise', () {
    expect(match('News <newsletter@x.example>'), 'sender:newsletter');
    expect(match('noreply@x.example'), 'sender:noreply');
  });

  test('role addresses colleagues use are not noise', () {
    for (final from in [
      'HR <hr@corp.example>',
      'IT <it@corp.example>',
      'Kanzlei <info@steuer.example>',
      'Security <security@corp.example>',
    ]) {
      expect(match(from), isNull, reason: from);
    }
  });

  test('unsubscribe footers in en, de, ar', () {
    expect(match('a@b.example', body: 'Click to Unsubscribe.'), isNotNull);
    expect(match('a@b.example', body: 'Hier abmelden.'), isNotNull);
    expect(match('a@b.example', body: 'لإلغاء الاشتراك اضغط هنا'), isNotNull);
  });

  test('ordinary German "abmelden" in work mail is not noise', () {
    expect(
      match('a@corp.example', body: 'Ich muss mich für morgen abmelden.'),
      isNull,
    );
  });

  // Guards against the rules hiding real mail in the spike test set.
  // (Recall on noise is reported by the batch run, not asserted here, to
  // avoid tuning rules to this small set.)
  test('no labelled non-noise test message matches a rule', () {
    final ds = TestDataset.parse(
      File('spike/testdata/messages.json').readAsStringSync(),
      File('spike/testdata/labels.json').readAsStringSync(),
    );
    for (final m in ds.messages) {
      if (ds.labels[m.id]!.category == TriageCategory.noise) continue;
      expect(
        matchNoiseRule(from: m.from, subject: m.subject, body: m.body),
        isNull,
        reason: m.id,
      );
    }
  });
}
