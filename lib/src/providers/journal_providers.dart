import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/journal_entry.dart';
import '../repositories/journal_repository.dart';
import '../storage/local_storage.dart';

final journalBoxProvider =
    Provider<Box<JournalEntry>>((ref) => Hive.box<JournalEntry>(HiveBoxes.journalEntries));

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  return HiveJournalRepository(ref.watch(journalBoxProvider));
});

class JournalListNotifier extends StreamNotifier<List<JournalEntry>> {
  JournalRepository get _repository => ref.read(journalRepositoryProvider);

  @override
  Stream<List<JournalEntry>> build() => _repository.watchAll();

  Future<void> addEntry(JournalEntry entry) => _repository.add(entry);

  Future<void> updateEntry(JournalEntry entry) => _repository.update(entry);

  Future<void> deleteEntry(String id) => _repository.delete(id);

  JournalEntry? getByDate(DateTime date) => _repository.getByDate(date);
}

final journalListProvider =
    StreamNotifierProvider<JournalListNotifier, List<JournalEntry>>(
  JournalListNotifier.new,
);
