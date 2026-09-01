import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/journal_entry.dart';
import 'hive_repository_utils.dart';

/// CRUD access to [JournalEntry] entries.
abstract class JournalRepository {
  Stream<List<JournalEntry>> watchAll();

  List<JournalEntry> getAll();

  JournalEntry? getById(String id);

  /// The entry dated exactly [date] (compared by calendar day), if any.
  JournalEntry? getByDate(DateTime date);

  Future<void> add(JournalEntry entry);

  Future<void> update(JournalEntry entry);

  Future<void> delete(String id);
}

class HiveJournalRepository implements JournalRepository {
  HiveJournalRepository(this._box);

  final Box<JournalEntry> _box;

  @override
  Stream<List<JournalEntry>> watchAll() => watchBoxValues(_box);

  @override
  List<JournalEntry> getAll() => _box.values.toList(growable: false);

  @override
  JournalEntry? getById(String id) => _box.get(id);

  @override
  JournalEntry? getByDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    for (final entry in _box.values) {
      final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
      if (entryDate == normalized) return entry;
    }
    return null;
  }

  @override
  Future<void> add(JournalEntry entry) => _box.put(entry.id, entry);

  @override
  Future<void> update(JournalEntry entry) => _box.put(entry.id, entry);

  @override
  Future<void> delete(String id) => _box.delete(id);
}
