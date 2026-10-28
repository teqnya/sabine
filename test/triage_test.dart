import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sabine/core/ai/triage.dart';

void main() {
  group('parseTriage', () {
    test('parses valid output', () {
      final r = parseTriage(
        '{"category":"needs_decision","summary":" Pick A or B "}',
      );
      expect(r.category, TriageCategory.needsDecision);
      expect(r.summary, 'Pick A or B');
    });

    test('tolerates chatter around the JSON object', () {
      final r = parseTriage(
        'Sure! {"category":"noise","summary":"Newsletter"} Done.',
      );
      expect(r.category, TriageCategory.noise);
    });

    test('rejects unknown category', () {
      expect(
        () => parseTriage('{"category":"spam","summary":"x"}'),
        throwsA(isA<TriageParseException>()),
      );
    });

    test('rejects missing summary', () {
      expect(
        () => parseTriage('{"category":"fyi"}'),
        throwsA(isA<TriageParseException>()),
      );
    });

    test('rejects non-JSON', () {
      expect(() => parseTriage('urgent'), throwsA(isA<TriageParseException>()));
    });
  });

  test('schema enum matches TriageCategory', () {
    final schema = jsonDecode(
      File('lib/core/ai/schemas/triage.v1.json').readAsStringSync(),
    );
    final values = (schema['properties']['category']['enum'] as List)
        .cast<String>();
    expect(values, TriageCategory.values.map((c) => c.wire).toList());
  });

  group('renderPrompt', () {
    test('fills all placeholders of triage.v1', () {
      final template = File('lib/core/ai/prompts/triage.v1.txt')
          .readAsStringSync();
      final out = renderPrompt(template, {
        'from': 'a',
        'subject': 'b',
        'date': 'c',
        'body': 'd',
      });
      expect(out, isNot(contains('{{')));
    });

    test('throws on missing value', () {
      expect(() => renderPrompt('{{x}}', {}), throwsArgumentError);
    });
  });
}
