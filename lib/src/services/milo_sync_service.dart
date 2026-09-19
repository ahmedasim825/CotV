import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reminder.dart';
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

/// Reads and writes the synced entities against a backend.
///
/// Abstract for the same reason the repositories are: it is the seam the
/// engine's tests stand two devices up against one shared fake remote
/// through, which is the only way to exercise a conflict without two
/// machines and a stopwatch.
abstract class MiloSyncService {
  Future<List<RemoteRecord<Task>>> fetchTasks(String? since);
  Future<void> pushTasks(Iterable<Task> tasks);

  Future<List<RemoteRecord<Reminder>>> fetchReminders(String? since);
  Future<void> pushReminders(Iterable<Reminder> reminders);

  Future<List<RemoteRecord<Subject>>> fetchSubjects(String? since);
  Future<void> pushSubjects(Iterable<Subject> subjects);

  Future<List<RemoteRecord<StudyLog>>> fetchStudyLogs(String? since);
  Future<void> pushStudyLogs(Iterable<StudyLog> logs);

  /// Every synced setting the server holds, with the newest server cursor
  /// across the batch.
  Future<(Map<String, RemoteSetting>, String?)> fetchSettings(String? since);

  Future<void> pushSettings(
    Map<String, Object?> values,
    int clientUpdatedAtMillis,
  );

  // Chat travels as rows rather than models, matching ChatSyncRepository:
  // the sync columns live on the SQLite tables, not on ChatSession or
  // ChatMessage, and putting them on the models would add sync metadata to
  // a Hive type only the legacy box still uses.
  Future<List<RemoteRecord<Map<String, Object?>>>> fetchChatSessions(
    String? since,
  );

  Future<void> pushChatSessions(Iterable<Map<String, Object?>> rows);

  Future<List<RemoteRecord<Map<String, Object?>>>> fetchChatMessages(
    String? since,
  );

  Future<void> pushChatMessages(Iterable<Map<String, Object?>> rows);
}

/// [MiloSyncService] against Supabase.
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
class SupabaseMiloSyncService implements MiloSyncService {
  SupabaseMiloSyncService(this._client);

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

  @override
  Future<List<RemoteRecord<Task>>> fetchTasks(String? since) =>
      _fetch('tasks', since, taskFromRow);

  @override
  Future<void> pushTasks(Iterable<Task> tasks) =>
      _push('tasks', tasks.map(taskToRow));

  // ---------------------------------------------------------------------
  // Reminders
  // ---------------------------------------------------------------------

  @override
  Future<List<RemoteRecord<Reminder>>> fetchReminders(String? since) =>
      _fetch('reminders', since, reminderFromRow);

  @override
  Future<void> pushReminders(Iterable<Reminder> reminders) =>
      _push('reminders', reminders.map(reminderToRow));

  // ---------------------------------------------------------------------
  // Study
  // ---------------------------------------------------------------------

  @override
  Future<List<RemoteRecord<Subject>>> fetchSubjects(String? since) =>
      _fetch('subjects', since, subjectFromRow);

  @override
  Future<void> pushSubjects(Iterable<Subject> subjects) =>
      _push('subjects', subjects.map(subjectToRow));

  @override
  Future<List<RemoteRecord<StudyLog>>> fetchStudyLogs(String? since) =>
      _fetch('study_logs', since, studyLogFromRow);

  @override
  Future<void> pushStudyLogs(Iterable<StudyLog> logs) =>
      _push('study_logs', logs.map(studyLogToRow));

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  /// Every synced setting the server holds, keyed as [syncedSettingKeys]
  /// names them, with the newest server cursor across the batch.
  @override
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

  @override
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
  // Chat
  // ---------------------------------------------------------------------

  @override
  Future<List<RemoteRecord<Map<String, Object?>>>> fetchChatSessions(
    String? since,
  ) =>
      _fetch('chat_sessions', since, chatSessionFromRow);

  @override
  Future<void> pushChatSessions(Iterable<Map<String, Object?>> rows) =>
      _push('chat_sessions', rows.map(chatSessionToRow));

  @override
  Future<List<RemoteRecord<Map<String, Object?>>>> fetchChatMessages(
    String? since,
  ) =>
      _fetch('chat_messages', since, chatMessageFromRow);

  @override
  Future<void> pushChatMessages(Iterable<Map<String, Object?>> rows) =>
      _push('chat_messages', rows.map(chatMessageToRow));

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
      'is_study': task.isStudy,
      'subject_id': task.subjectId,
      // Names rather than indices, for the reason the priority column above
      // documents: reordering an enum must not re-point rows the server
      // already holds.
      'repeat_rule': task.repeat.name,
      'early_reminder': task.earlyReminder.name,
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
    isStudy: (row['is_study'] as bool?) ?? false,
    subjectId: row['subject_id'] as String?,
    repeat: _repeat(row['repeat_rule'] as String?),
    earlyReminder: _earlyReminder(row['early_reminder'] as String?),
    updatedAtMillis: millis,
    isDeleted: (row['deleted'] as bool?) ?? false,
    syncedAtMillis: millis,
  );
}

Map<String, Object?> reminderToRow(Reminder reminder) => {
      'id': reminder.id,
      'title': reminder.title,
      'due_at': _instant(reminder.dueAt),
      'is_completed': reminder.isCompleted,
      // The enum's name, not its index — same as tasks, and for the same
      // reason: reordering `TaskPriority` must not silently re-rank every
      // row the server already holds.
      'priority': reminder.priority.name,
      ..._syncColumns(reminder.updatedAtMillis, reminder.isDeleted),
    };

Reminder reminderFromRow(Map<String, dynamic> row) {
  final millis = _millis(row);
  return Reminder(
    id: row['id'] as String,
    title: row['title'] as String,
    // Non-null where a task's due date is nullable: a reminder with no
    // moment attached is not a reminder, and the column is NOT NULL.
    dueAt: _dateTime(row['due_at'])!,
    isCompleted: (row['is_completed'] as bool?) ?? false,
    priority: _priority(row['priority'] as String?),
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

// Chat rows, mapped between the SQLite shape and the Postgres one. The
// local `updated_at` is already device milliseconds, so it *is*
// `client_updated_at`; SQLite has no boolean, so `deleted` is 0/1 there and
// a bool here.

Map<String, Object?> chatSessionToRow(Map<String, Object?> local) => {
      'id': local['id'],
      'title': local['title'],
      'created_at': _instantFromMillis(local['created_at']),
      'client_updated_at': (local['client_updated_at'] as num?)?.toInt() ?? 0,
      'deleted': _flag(local['deleted']),
    };

Map<String, Object?> chatSessionFromRow(Map<String, dynamic> row) => {
      'id': row['id'],
      'title': row['title'],
      'created_at': _millisFromInstant(row['created_at']),
      'client_updated_at': (row['client_updated_at'] as num).toInt(),
      'deleted': (row['deleted'] as bool?) ?? false ? 1 : 0,
    };

Map<String, Object?> chatMessageToRow(Map<String, Object?> local) => {
      'id': local['id'],
      'session_id': local['session_id'],
      'role': local['role'],
      'content': local['content'],
      'timestamp': _instantFromMillis(local['timestamp']),
      'tokens_used': local['tokens_used'],
      'client_updated_at': (local['client_updated_at'] as num?)?.toInt() ?? 0,
      'deleted': _flag(local['deleted']),
    };

Map<String, Object?> chatMessageFromRow(Map<String, dynamic> row) => {
      'id': row['id'],
      'session_id': row['session_id'],
      'role': row['role'],
      'content': row['content'],
      'timestamp': _millisFromInstant(row['timestamp']),
      'tokens_used': (row['tokens_used'] as num?)?.toInt(),
      'client_updated_at': (row['client_updated_at'] as num).toInt(),
      'deleted': (row['deleted'] as bool?) ?? false ? 1 : 0,
    };

bool _flag(Object? value) => (value as num?)?.toInt() == 1;

String? _instantFromMillis(Object? millis) => millis == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch((millis as num).toInt(), isUtc: true)
        .toIso8601String();

int _millisFromInstant(Object? value) =>
    DateTime.parse(value as String).millisecondsSinceEpoch;

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

TaskPriority _priority(String? name) {
  for (final value in TaskPriority.values) {
    if (value.name == name) return value;
  }
  return TaskPriority.medium;
}

TaskRepeat _repeat(String? name) {
  for (final value in TaskRepeat.values) {
    if (value.name == name) return value;
  }
  // A rule this build does not know is a rule it cannot honour, and silently
  // repeating on a schedule nobody chose is worse than not repeating.
  return TaskRepeat.never;
}

TaskEarlyReminder _earlyReminder(String? name) {
  for (final value in TaskEarlyReminder.values) {
    if (value.name == name) return value;
  }
  return TaskEarlyReminder.never;
}
