import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journal_entry.dart';
import '../models/journal_view.dart';
import 'journal_providers.dart';

/// The journal's search box.
class JournalQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;

  void clear() => state = '';
}

final journalQueryProvider =
    NotifierProvider<JournalQueryNotifier, String>(JournalQueryNotifier.new);

/// The selected tag, or null for "all tags". Tapping the active tag clears
/// it, so the row doubles as its own reset.
class JournalTagFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void toggle(String tag) => state = state == tag ? null : tag;

  void clear() => state = null;
}

final journalTagFilterProvider =
    NotifierProvider<JournalTagFilterNotifier, String?>(
  JournalTagFilterNotifier.new,
);

/// The selected mood, or null for "any mood".
class JournalMoodFilterNotifier extends Notifier<JournalMood?> {
  @override
  JournalMood? build() => null;

  void toggle(JournalMood mood) => state = state == mood ? null : mood;

  void clear() => state = null;
}

final journalMoodFilterProvider =
    NotifierProvider<JournalMoodFilterNotifier, JournalMood?>(
  JournalMoodFilterNotifier.new,
);

/// Every tag in use, most-used first — the filter row's contents.
final journalTagsProvider = Provider<List<String>>((ref) {
  final entries = ref.watch(journalListProvider).value;
  if (entries == null) return const [];
  return collectTags(entries);
});

/// The entries the journal list should show: the repository stream, run
/// through the active filters and ordered newest first.
///
/// Kept as a derived provider (rather than filtering inside the widget) so
/// the screen holds no copy of the list and a Hive write shows up without
/// the screen doing anything.
final visibleJournalEntriesProvider =
    Provider<AsyncValue<List<JournalEntry>>>((ref) {
  final entriesAsync = ref.watch(journalListProvider);
  final query = ref.watch(journalQueryProvider);
  final tag = ref.watch(journalTagFilterProvider);
  final mood = ref.watch(journalMoodFilterProvider);

  return entriesAsync.whenData(
    (entries) => sortJournalByDate(
      filterJournal(entries, query: query, tag: tag, mood: mood),
    ),
  );
});

/// True when anything is narrowing the list — drives the "clear filters"
/// affordance and the wording of the empty state.
final journalHasFiltersProvider = Provider<bool>((ref) {
  return ref.watch(journalQueryProvider).trim().isNotEmpty ||
      ref.watch(journalTagFilterProvider) != null ||
      ref.watch(journalMoodFilterProvider) != null;
});
