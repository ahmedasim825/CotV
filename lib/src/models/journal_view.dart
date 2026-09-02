import 'journal_entry.dart';

extension JournalMoodX on JournalMood {
  String get label {
    switch (this) {
      case JournalMood.great:
        return 'Great';
      case JournalMood.good:
        return 'Good';
      case JournalMood.neutral:
        return 'Neutral';
      case JournalMood.low:
        return 'Low';
      case JournalMood.difficult:
        return 'Difficult';
    }
  }

  /// 2 = best, -2 = hardest. The single source of truth for mood order —
  /// [orderedMoods] is derived from it.
  int get valence {
    switch (this) {
      case JournalMood.great:
        return 2;
      case JournalMood.good:
        return 1;
      case JournalMood.neutral:
        return 0;
      case JournalMood.low:
        return -1;
      case JournalMood.difficult:
        return -2;
    }
  }
}

/// Best-to-hardest, the order the mood picker and filter row render in.
final List<JournalMood> orderedMoods = List.unmodifiable(
  JournalMood.values.toList()
    ..sort((a, b) => b.valence.compareTo(a.valence)),
);

/// A plain-text preview of a markdown body, for entry cards.
///
/// Strips block markers and inline emphasis rather than rendering them, so
/// a card never shows raw `##` or `**` — and collapses whitespace so a
/// multi-paragraph entry still previews on two lines.
String journalExcerpt(String markdown, {int maxChars = 160}) {
  var text = markdown;

  // Fenced code blocks: keep the code, drop the fences.
  text = text.replaceAll(RegExp(r'^```.*$', multiLine: true), '');
  // Block markers at the start of a line.
  text = text.replaceAll(
    RegExp(r'^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+|\d+\.\s+)', multiLine: true),
    '',
  );
  // Horizontal rules.
  text = text.replaceAll(RegExp(r'^\s*([-*_])\s*\1\s*\1[\s\S]*?$', multiLine: true), '');
  // Links: keep the label, drop the target.
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\(([^)]*)\)'),
    (m) => m.group(1) ?? '',
  );
  // Inline emphasis and code.
  text = text.replaceAll(RegExp(r'(\*\*|__|\*|_|`)'), '');

  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars).trimRight()}…';
}

/// Every distinct tag across [entries], most-used first, then alphabetical.
List<String> collectTags(List<JournalEntry> entries) {
  final counts = <String, int>{};
  for (final entry in entries) {
    for (final tag in entry.tags) {
      final normalized = tag.trim();
      if (normalized.isEmpty) continue;
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
  }

  final tags = counts.keys.toList();
  tags.sort((a, b) {
    final byCount = counts[b]!.compareTo(counts[a]!);
    if (byCount != 0) return byCount;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return List.unmodifiable(tags);
}

/// Narrows [entries] to those matching every supplied filter. A null or
/// empty filter is not applied.
List<JournalEntry> filterJournal(
  List<JournalEntry> entries, {
  String query = '',
  String? tag,
  JournalMood? mood,
}) {
  final needle = query.trim().toLowerCase();

  return entries.where((entry) {
    if (mood != null && entry.mood != mood) return false;
    if (tag != null && !entry.tags.any((t) => t == tag)) return false;
    if (needle.isEmpty) return true;

    if (entry.content.toLowerCase().contains(needle)) return true;
    return entry.tags.any((t) => t.toLowerCase().contains(needle));
  }).toList(growable: false);
}

/// Newest first, with the entry id as a tiebreaker so two entries on the
/// same date keep a stable order between rebuilds.
List<JournalEntry> sortJournalByDate(List<JournalEntry> entries) {
  final ordered = [...entries];
  ordered.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  });
  return List.unmodifiable(ordered);
}

/// Normalizes a user-typed tag: trimmed, lower-cased, no leading `#`, and
/// inner whitespace collapsed to single hyphens, so "  Deep Work " and
/// "#deep work" both land on `deep-work`.
String normalizeTag(String raw) {
  final trimmed = raw.trim().replaceAll(RegExp(r'^#+'), '').trim();
  if (trimmed.isEmpty) return '';
  return trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
}
