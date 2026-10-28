import 'dart:convert';

import '../../core/ai/triage.dart';

/// A synthetic test message (spike/testdata/messages.json).
class TestMessage {
  const TestMessage({
    required this.id,
    required this.language,
    required this.from,
    required this.subject,
    required this.date,
    required this.body,
  });

  factory TestMessage.fromJson(Map<String, dynamic> json) => TestMessage(
    id: json['id'] as String,
    language: json['language'] as String,
    from: json['from'] as String,
    subject: json['subject'] as String,
    date: json['date'] as String,
    body: json['body'] as String,
  );

  final String id;

  /// ISO 639-1: de, en, ar.
  final String language;
  final String from;
  final String subject;
  final String date;
  final String body;
}

/// Ground truth for one message (spike/testdata/labels.json).
class TestLabel {
  const TestLabel({
    required this.id,
    required this.category,
    this.expectedDates = const [],
    this.expectedTasks = const [],
    this.isMeetingRequest = false,
  });

  factory TestLabel.fromJson(Map<String, dynamic> json) {
    final wire = json['category'] as String;
    final category = TriageCategory.fromWire(wire);
    if (category == null) {
      throw FormatException('label ${json['id']}: unknown category "$wire"');
    }
    return TestLabel(
      id: json['id'] as String,
      category: category,
      expectedDates: _stringList(json['expected_dates']),
      expectedTasks: _stringList(json['expected_tasks']),
      isMeetingRequest: json['meeting_request'] as bool? ?? false,
    );
  }

  final String id;
  final TriageCategory category;

  /// ISO 8601 dates/datetimes the extractor should find.
  final List<String> expectedDates;
  final List<String> expectedTasks;
  final bool isMeetingRequest;

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? const []).cast<String>();
}

class TestDataset {
  TestDataset(this.messages, this.labels);

  /// Parses both files and checks that every message has exactly one label.
  factory TestDataset.parse(String messagesJson, String labelsJson) {
    final messages = (jsonDecode(messagesJson) as List<dynamic>)
        .map((e) => TestMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    final labels = <String, TestLabel>{};
    for (final e in jsonDecode(labelsJson) as List<dynamic>) {
      final label = TestLabel.fromJson(e as Map<String, dynamic>);
      if (labels.containsKey(label.id)) {
        throw FormatException('duplicate label for ${label.id}');
      }
      labels[label.id] = label;
    }
    final ids = messages.map((m) => m.id).toSet();
    if (ids.length != messages.length) {
      throw const FormatException('duplicate message id');
    }
    final unlabeled = ids.difference(labels.keys.toSet());
    final orphaned = labels.keys.toSet().difference(ids);
    if (unlabeled.isNotEmpty || orphaned.isNotEmpty) {
      throw FormatException(
        'labels mismatch: unlabeled=$unlabeled, orphaned=$orphaned',
      );
    }
    return TestDataset(messages, labels);
  }

  final List<TestMessage> messages;
  final Map<String, TestLabel> labels;
}
