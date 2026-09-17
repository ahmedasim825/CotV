import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/habit.dart';
import '../models/study_log.dart';
import '../models/subject.dart';
import '../models/task.dart';
import 'sync_merge.dart';

/// Anything the sync backend refused, already phrased for a StatusCard.
class MiloSyncException implements Exception {
  const MiloSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One record as it arrived, alongside the server clock that ordered it.
///
/// The cursor is kept beside the record rather than on it because it is
/// not a property of the record at all — it is this server's opinion of
/// when the row last moved, and the only thing the two devices can agree
/// to sort by.
class RemoteRecord<T> {
  const RemoteRecord(this.record, this.cursor);

  final T record;
  final String cursor;
}

/// Reads and writes tasks, habits, subjects and study logs against
/// Supabase.
///
/// Every method assumes a signed-in user and passes `user_id` explicitly.
/// That is belt and braces: row-level security would reject a mismatched
/// id anyway, but sending it means the failure is a clear error rather
/// than a silently empty result.
///
/// Records arrive carrying the timestamps they were written with —
/// `client_updated_at` becomes `updatedAtMillis`, and `syncedAtMillis` is
/// set to match so a pulled record reads as clean. A pulled record stamped
/// with the local clock instead would look edited forever, and the two
/// devices would push it back and forth indefinitely.
class MiloSyncService {
  MiloSyncService(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const MiloSyncException('Sign in to sync this device.');
    }
    return id;
  }

  // ---------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------

  Future<List<RemoteRecord<Task>>> fetchTasks(String? since) =>
      _fetch('tasks', since, taskFromRow);

  Future<void> pushTasks(Iterable<Task> tasks) =>
      _push('tasks', tasks.map(taskToRow));

  // ---------------------------------------------------------------------
  // Habits
  // ---------------------------------------------------------------------

  Future<List<RemoteRecord<Habit>>> fetchHabits(String? since) =>
      _fetch('habits', since, habitFromRow);

  Future<void> pushHabits(Iterable<Habit> habits) =>
      _push('habits', habits.map(habitToRow));

  // ---------------------------------------------------------------------
  // Study
  // ---------------------------------------------------------------------

  Future<List<RemoteRecord<Subject>>> fetchSubjects(String? since) =>
      _fetch('subjects', since, subjectFromRow);

  Future<void> pushSubjects(Iterable<Subject> subjects) =>
      _push('subjects', subjects.map(subjectToRow));

  Future<List<RemoteRecord<StudyLog>>> fetchStudyLogs(String? since) =>
      _fetch('study_logs', since, studyLogFromRow);

  Future<void> pushStudyLogs(Iterable<StudyLog> logs) =>
      _push('study_logs', logs.map(studyLogToRow));

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  /// Every synced setting the server holds, keyed as [syncedSettingKeys]
  /// names them, with the newest server cursor across the batch.
  Future<(Map<String, RemoteSetting>, String?)> fetchSettings(
    String? since,
  ) async {
    final rows = await _guard(
      () {
        final query = _client
            .from('user_settings')
            .select()
            .eq('user_id', _userId);
        return (since == null ? query : query.gt('updated_at', since))
            .order('updated_at');
      },
      'Could not load your settings.',
    );

    final settings = <String, RemoteSetting>{};
    String? cursor;
    for (final row in rows) {
      final key = row['key'] as String;
      cursor = row['updated_at'] as String?;
      // Filtered on the way in as well as on the way out: a key the server
      // holds from a newer build is not one this build knows how to apply.
      if (!syncedSettingKeys.contains(key)) continue;
      settings[key] = RemoteSetting(
        row['value'],
        (row['client_updated_at'] as num).toInt(),
      );
    }
    return (settings, cursor);
  }

  Future<void> pushSettings(
    Map<String, Object?> values,
    int clientUpdatedAtMillis,
  ) async {
    final rows = [
      for (final entry in values.entries)
        if (syncedSettingKeys.contains(entry.key))
          {
            'user_id': _userId,
            'key': entry.key,
            'value': entry.value,
            'client_updated_at': clientUpdatedAtMillis,
          },
    ];
    if (rows.isEmpty) return;
    await _guard(
      () => _client
          .from('user_settings')
          .upsert(rows, onConflict: 'user_id,key'),
      'Could not save your settings.',
    );
  }

  // ---------------------------------------------------------------------
  // Shared plumbing
  // ---------------------------------------------------------------------

  Future<List<RemoteRecord<T>>> _fetch<T>(
    String table,
    String? since,
    T Function(Map<String, dynamic>) fromRow,
  ) async {
    final rows = await _guard(
      () {
        final query = _client.from(table).select().eq('user_id', _userId);
        // Strictly greater than, so a cursor at the newest row we have
        // fetches nothing rather than re-fetching that row every cycle.
        return (since == null ? query : query.gt('updated_at', since))
            .order('updated_at');
      },
      'Could not load your $table.',
    );

    return [
      for (final row in rows)
        RemoteRecord(fromRow(row), row['updated_at'] as String),
    ];
  }

  Future<void> _push(
    String table,
    Iterable<Map<String, Object?>> rows,
  ) async {
    final payload = [
      for (final row in rows) {...row, 'user_id': _userId},
    ];
    if (payload.isEmpty) return;
    await _guard(
      () => _client.from(table).upsert(payload, onConflict: 'user_id,id'),
      'Could not save your $table.',
    );
  }

  /// Turns Supabase's own exceptions into one type carrying a message fit
  /// to show, so no screen has to know about PostgrestException.
  Future<T> _guard<T>(Future<T> Function() action, String whenFailed) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw MiloSyncException('$whenFailed ${error.message}');
    } on AuthException catch (error) {
      throw MiloSyncException('$whenFailed ${error.message}');
    } on SocketException {
      throw MiloSyncException('$whenFailed No connection.');
    }
  }
}

// -----------------------------------------------------------------------
// Row mapping
//
// Top-level rather than private so the mapping can be tested without a
// client: every one of these is a pure function over a map.
// -----------------------------------------------------------------------

Map<String, Object?> taskToRow(Task task) => {
      'id': task.id,
      'title': task.title,
      'description': task.description,
      'due_date': _instant(task.dueDate),
      'is_completed': task.isCompleted,
      'category': task.category,
      'priority': task.priority.name,
      'created_at': _instant(task.createdAt),
      'has_reminder': task.hasReminder,
      ..._syncColumns(task.updatedAtMillis, task.isDeleted),
    };

Task taskFromRow(Map<String, dynamic> row) {
  final millis = _millis(row);
  return Task(
    id: row['id'] as String,
    title: row['title'] as String,
    description: (row['description'] as String?) ?? '',
    dueDate: _dateTime(row['due_date']),
    isCompleted: (row['is_completed'] as bool?) ?? false,
    category: (row['category'] as String?) ?? 'General',
    priority: _priority(row['priority'] as String?),
    createdAt: _dateTime(row['created_at']),
    hasReminder: (row['has_reminder'] as bool?) ?? false,
    updatedAtMillis: millis,
    isDeleted: (row['deleted'] as bool?) ?? false,
    syncedAtMillis: millis,
  );
}

Map<String, Object?> habitToRow(Habit habit) => {
      'id': habit.id,
      'title': habit.title,
      'frequency': habit.frequency.name,
      // Calendar dates, formatted rather than sent as instants. A local
      // midnight converted to UTC lands on the previous day for anyone east
      // of Greenwich, which would move every check-in by a day.
      'completed_dates': habit.completedDates.map(_dateOnly).toList(),
      'color_hex': habit.colorHex,
      ..._syncColumns(habit.updatedAtMillis, habit.isDeleted),
    };

Habit habitFromRow(Map<String, dynamic> row) {
  final millis = _millis(row);
  final dates = (row['completed_dates'] as List?) ?? const [];
  return Habit(
    id: row['id'] as String,
    title: row['title'] as String,
    frequency: _frequency(row['frequency'] as String?),
    completedDates: [
      for (final date in dates) _calendarDate(date as String),
    ],
    // streakCount is not a column: it is recomputed from the dates by the
    // merge, since a stored count can disagree with the set beneath it.
    streakCount: 0,
    colorHex: (row['color_hex'] as String?) ?? '#D8A657',
    updatedAtMillis: millis,
    isDeleted: (row['deleted'] as bool?) ?? false,
    syncedAtMillis: millis,
  );
}

Map<String, Object?> subjectToRow(Subject subject) => {
      'id': subject.id,
      'name': subject.name,
      'color_value': subject.colorValue,
      'created_at': _instant(subject.createdAt),
      ..._syncColumns(subject.updatedAtMillis, subject.isDeleted),
    };

Subject subjectFromRow(Map<String, dynamic> row) {
  final millis = _millis(row);
  return Subject(
    id: row['id'] as String,
    name: row['name'] as String,
    colorValue: (row['color_value'] as num).toInt(),
    createdAt: _dateTime(row['created_at']),
    updatedAtMillis: millis,
    isDeleted: (row['deleted'] as bool?) ?? false,
    syncedAtMillis: millis,
  );
}

Map<String, Object?> studyLogToRow(StudyLog log) => {
      'id': log.id,
      'subject_id': log.subjectId,
      'subject_name': log.subjectName,
      'duration_minutes': log.durationMinutes,
      'timestamp': _instant(log.timestamp),
      ..._syncColumns(log.updatedAtMillis, log.isDeleted),
    };

StudyLog studyLogFromRow(Map<String, dynamic> row) {
  final millis = _millis(row);
  return StudyLog(
    id: row['id'] as String,
    subjectId: row['subject_id'] as String,
    subjectName: row['subject_name'] as String,
    durationMinutes: (row['duration_minutes'] as num).toInt(),
    timestamp: _dateTime(row['timestamp'])!,
    updatedAtMillis: millis,
    isDeleted: (row['deleted'] as bool?) ?? false,
    syncedAtMillis: millis,
  );
}

Map<String, Object?> _syncColumns(int? updatedAtMillis, bool isDeleted) => {
      // Never null on the wire. A record reaching the push path without a
      // stamp would sort as older than everything and lose to any remote
      // row; the migration backfills for exactly that reason, and this is
      // the second line of defence.
      'client_updated_at':
          updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
      'deleted': isDeleted,
    };

int _millis(Map<String, dynamic> row) =>
    (row['client_updated_at'] as num).toInt();

/// An instant on the wire: always UTC, so the receiving device's zone
/// cannot change which moment it refers to.
String? _instant(DateTime? value) => value?.toUtc().toIso8601String();

DateTime? _dateTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();

/// A calendar date on the wire — no time, no zone.
String _dateOnly(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The inverse: local midnight on that calendar day, which is the form
/// every completion is stored and compared in.
DateTime _calendarDate(String value) {
  final parts = value.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

TaskPriority _priority(String? name) {
  for (final value in TaskPriority.values) {
    if (value.name == name) return value;
  }
  return TaskPriority.medium;
}

HabitFrequency _frequency(String? name) {
  for (final value in HabitFrequency.values) {
    if (value.name == name) return value;
  }
  return HabitFrequency.daily;
}
