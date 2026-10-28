import 'dart:convert';

enum TriageCategory {
  urgent('urgent'),
  needsDecision('needs_decision'),
  fyi('fyi'),
  noise('noise');

  const TriageCategory(this.wire);

  /// Value used in JSON (schema `triage.v1`).
  final String wire;

  static TriageCategory? fromWire(String value) {
    for (final c in values) {
      if (c.wire == value) return c;
    }
    return null;
  }
}

class TriageResult {
  const TriageResult({required this.category, required this.summary});

  final TriageCategory category;
  final String summary;
}

class TriageParseException implements Exception {
  TriageParseException(this.message, this.raw);

  final String message;
  final String raw;

  @override
  String toString() => 'TriageParseException: $message';
}

/// Parses and validates model output against schema `triage.v1`.
///
/// Even with grammar-constrained decoding, output is validated here so that
/// failures are surfaced honestly instead of silently defaulting (CLAUDE.md §2.7).
TriageResult parseTriage(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_extractJsonObject(raw));
  } on FormatException catch (e) {
    throw TriageParseException('invalid JSON: ${e.message}', raw);
  }
  if (decoded is! Map<String, dynamic>) {
    throw TriageParseException('expected a JSON object', raw);
  }
  final category = decoded['category'];
  final summary = decoded['summary'];
  if (category is! String) {
    throw TriageParseException('missing "category"', raw);
  }
  final parsed = TriageCategory.fromWire(category);
  if (parsed == null) {
    throw TriageParseException('unknown category "$category"', raw);
  }
  if (summary is! String) {
    throw TriageParseException('missing "summary"', raw);
  }
  return TriageResult(category: parsed, summary: summary.trim());
}

/// Tolerates leading/trailing chatter around a single JSON object, which
/// unconstrained small models often emit.
String _extractJsonObject(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end < start) return raw;
  return raw.substring(start, end + 1);
}

/// Fills `{{placeholder}}` slots in a versioned prompt template.
String renderPrompt(String template, Map<String, String> values) {
  return template.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (m) {
    final key = m.group(1)!;
    final value = values[key];
    if (value == null) {
      throw ArgumentError('prompt placeholder "$key" has no value');
    }
    return value;
  });
}
