/// Deterministic noise detection that runs before the model (CLAUDE.md §6:
/// prefer rules where they are accurate enough). A match skips inference.
///
/// Rules are deliberately conservative: a false positive hides a real email,
/// which is worse than letting the model look at an advert. With live mail the
/// `List-Unsubscribe` header will be the strongest signal; the spike test set
/// has no headers, so only sender and text patterns are used here.
library;

/// Mailbox names that bulk senders use. Generic role addresses such as
/// `info@`, `hr@` or `it@` are intentionally absent: colleagues write from them.
const _bulkSenderLocalParts = {
  'newsletter',
  'newsletters',
  'news',
  'weekly',
  'digest',
  'marketing',
  'promo',
  'promotions',
  'offers',
  'deals',
  'notifications',
  'notification',
  'noreply',
  'no-reply',
  'donotreply',
  'do-not-reply',
  'events',
  'versand',
  'shipping',
};

/// Unsubscribe footers (en, de, ar) and prize-scam phrases. Lower-cased.
/// German uses full phrases: a bare "abmelden" also appears in normal work
/// mail ("ich muss mich für morgen abmelden").
const _bulkPhrases = [
  'unsubscribe',
  'hier abmelden',
  'newsletter abmelden',
  'newsletter abbestellen',
  'إلغاء الاشتراك',
  'sie haben gewonnen',
  'you have won',
  'you\'ve won',
  'لقد ربحت',
];

final _address = RegExp(r'<([^>]+)>|(\S+@\S+)');

/// Returns the name of the matching rule, or null if the model should decide.
String? matchNoiseRule({
  required String from,
  required String subject,
  required String body,
}) {
  final m = _address.firstMatch(from);
  final address = (m?.group(1) ?? m?.group(2) ?? '').toLowerCase();
  final at = address.indexOf('@');
  if (at > 0) {
    final local = address.substring(0, at);
    if (_bulkSenderLocalParts.contains(local)) return 'sender:$local';
  }
  final text = '$subject\n$body'.toLowerCase();
  for (final phrase in _bulkPhrases) {
    if (text.contains(phrase)) return 'phrase:$phrase';
  }
  return null;
}
