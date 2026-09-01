import 'package:hive_ce/hive_ce.dart';

part 'journal_entry.g.dart';

/// Self-reported mood attached to a [JournalEntry].
@HiveType(typeId: 6)
enum JournalMood {
  @HiveField(0)
  great,
  @HiveField(1)
  good,
  @HiveField(2)
  neutral,
  @HiveField(3)
  low,
  @HiveField(4)
  difficult,
}

/// A single dated journal entry with markdown content.
@HiveType(typeId: 5)
class JournalEntry {
  JournalEntry({
    required this.id,
    required this.date,
    this.content = '',
    this.mood = JournalMood.neutral,
    List<String>? tags,
  }) : tags = tags ?? const [];

  @HiveField(0)
  final String id;

  /// Midnight-normalized date this entry belongs to.
  @HiveField(1)
  final DateTime date;

  /// Markdown-formatted body.
  @HiveField(2)
  final String content;

  @HiveField(3)
  final JournalMood mood;

  @HiveField(4)
  final List<String> tags;

  JournalEntry copyWith({
    DateTime? date,
    String? content,
    JournalMood? mood,
    List<String>? tags,
  }) {
    return JournalEntry(
      id: id,
      date: date ?? this.date,
      content: content ?? this.content,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
    );
  }
}
