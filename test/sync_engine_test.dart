// The sync engine, driven as two devices against one shared remote.
//
// Two independent local stacks — separate Hive boxes, separate metadata,
// separate clocks — talking to one fake server. That is what makes a
// conflict reproducible: the alternative is two machines and a stopwatch.
//
// The property asserted throughout is **convergence**: after a bounded
// exchange the two devices hold the same record. Which one wins is a
// weaker claim and a less useful one — a rule that picked a consistent
// winner but left the pair disagreeing would still be broken.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/sync_stamped.dart';
import 'package:cotv/src/providers/auth_providers.dart';
import 'package:cotv/src/providers/nutrition_providers.dart'
    show syncErrorProvider;
import 'package:cotv/src/providers/study_providers.dart';
import 'package:cotv/src/providers/sync_providers.dart';
import 'package:cotv/src/repositories/study_log_repository.dart';
import 'package:cotv/src/repositories/subject_repository.dart';
import 'package:cotv/src/services/milo_sync_service.dart';
import 'package:cotv/src/storage/sync_metadata.dart';

/// A stand-in server that stores rows, not models.
///
/// Going through the real `*ToRow` / `*FromRow` functions means a mapping
/// bug fails these tests too, which is the point — a fake that traded
/// model objects would prove only that the merge maths works.
class _FakeRemote implements MiloSyncService {
  final Map<String, Map<String, Map<String, dynamic>>> _tables = {};

  /// Stands in for `now()` in the touch_updated_at trigger. Monotonic, and
  /// entirely unrelated to either device's clock — which is the point of
  /// having a server cursor at all.
  int _tick = 0;

  int pushedRows = 0;
  int fetchCalls = 0;

  String _stamp() {
    _tick++;
    return DateTime.utc(2026, 1, 1).add(Duration(seconds: _tick))
        .toIso8601String();
  }

  List<RemoteRecord<T>> _fetch<T>(
    String table,
    String? since,
    T Function(Map<String, dynamic>) fromRow,
  ) {
    fetchCalls++;
    final rows = (_tables[table] ?? const {}).values.toList()
      ..sort((a, b) =>
          (a['updated_at'] as String).compareTo(b['updated_at'] as String));
    return [
      for (final row in rows)
        if (since == null || (row['updated_at'] as String).compareTo(since) > 0)
          RemoteRecord(fromRow(row), row['updated_at'] as String),
    ];
  }

  void _push(String table, Iterable<Map<String, Object?>> rows) {
    final stored = _tables.putIfAbsent(table, () => {});
    for (final row in rows) {
      pushedRows++;
      // The trigger overwrites whatever the client sent.
      stored[row['id'] as String] = {...row, 'updated_at': _stamp()};
    }
  }

  @override
  Future<List<RemoteRecord<Subject>>> fetchSubjects(String? since) async =>
      _fetch('subjects', since, subjectFromRow);

  @override
  Future<void> pushSubjects(Iterable<Subject> subjects) async =>
      _push('subjects', subjects.map(subjectToRow));

  @override
  Future<List<RemoteRecord<StudyLog>>> fetchStudyLogs(String? since) async =>
      _fetch('study_logs', since, studyLogFromRow);

  @override
  Future<void> pushStudyLogs(Iterable<StudyLog> logs) async =>
      _push('study_logs', logs.map(studyLogToRow));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not synced yet');
}

/// A remote that refuses every push, to prove a failed cycle leaves local
/// records dirty rather than marking them clean.
class _OfflineRemote extends _FakeRemote {
  @override
  Future<void> pushSubjects(Iterable<Subject> subjects) async =>
      throw const MiloSyncException('No connection.');
}

/// One device: its own boxes, its own metadata, its own clock.
class _Device {
  _Device(this.name, this.remote, this.boxes, this.container, this.metadata);

  final String name;
  final _FakeRemote remote;
  final ({
    Box<Subject> subjects,
    Box<StudyLog> logs,
    Box<dynamic> meta,
  }) boxes;
  final ProviderContainer container;
  final SyncMetadata metadata;

  /// Advanced by hand so "A wrote before B" is a fact of the test rather
  /// than a race between two real clocks.
  int clock = 1000;

  SyncController get sync => container.read(syncControllerProvider.notifier);
  SubjectRepository get subjects =>
      container.read(subjectRepositoryProvider);
  StudyLogRepository get logs => container.read(studyLogRepositoryProvider);

  Future<void> syncNow() => sync.syncAll();

  void dispose() => container.dispose();
}

void main() {
  late Directory tempDir;
  late _FakeRemote remote;
  late List<_Device> devices;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_sync_engine_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapters();
    }
    remote = _FakeRemote();
    devices = [];
  });

  tearDown(() async {
    for (final device in devices) {
      device.dispose();
    }
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Two devices share one Hive directory but never one box: the boxes are
  /// named per device, which is the cheapest way to get two independent
  /// stacks without a second Hive instance.
  Future<_Device> device(String name, {_FakeRemote? using}) async {
    final server = using ?? remote;
    final boxes = (
      subjects: await Hive.openBox<Subject>('${name}_subjects'),
      logs: await Hive.openBox<StudyLog>('${name}_logs'),
      meta: await Hive.openBox<dynamic>('${name}_meta'),
    );
    final metadata = SyncMetadata(boxes.meta);

    late _Device built;
    final container = ProviderContainer(
      overrides: [
        isSignedInProvider.overrideWithValue(true),
        syncUserIdProvider.overrideWithValue('user-1'),
        miloSyncServiceProvider.overrideWithValue(server),
        syncMetadataProvider.overrideWithValue(metadata),
        subjectRepositoryProvider.overrideWithValue(
          HiveSubjectRepository(boxes.subjects, () => built.clock),
        ),
        studyLogRepositoryProvider.overrideWithValue(
          HiveStudyLogRepository(boxes.logs, () => built.clock),
        ),
      ],
    );

    built = _Device(name, server, boxes, container, metadata);
    devices.add(built);
    return built;
  }

  group('one device', () {
    test('a first sync pushes everything and pulls nothing', () async {
      final a = await device('a');
      await a.subjects.add(_subject('s1', 'Physiology'));

      await a.syncNow();

      expect(remote.pushedRows, 1);
      expect(a.boxes.subjects.get('s1')!.isDirty, isFalse,
          reason: 'a pushed record is clean until it is edited again');
    });

    test('a second sync with no local change writes nothing', () async {
      final a = await device('a');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      final after = remote.pushedRows;

      await a.syncNow();

      // Idempotence. A cycle that re-pushed unchanged rows would rewrite
      // every server row on every tick, and the other device would see
      // every record change every five minutes.
      expect(remote.pushedRows, after);
    });

    test('a failed push leaves the record dirty for the next attempt',
        () async {
      final offline = _OfflineRemote();
      final a = await device('a', using: offline);
      await a.subjects.add(_subject('s1', 'Physiology'));

      await a.syncNow();

      expect(a.boxes.subjects.get('s1')!.isDirty, isTrue);
      expect(a.container.read(syncErrorProvider), isNotNull);
    });
  });

  group('two devices', () {
    test('a record made on one appears on the other', () async {
      final a = await device('a');
      final b = await device('b');

      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();

      expect(b.subjects.getAll().map((s) => s.name), ['Physiology']);
      expect(b.boxes.subjects.get('s1')!.isDirty, isFalse,
          reason: 'a pulled record must not read as a local edit');
    });

    test('a pulled record is not pushed straight back', () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();

      await b.syncNow();
      final after = remote.pushedRows;
      await b.syncNow();

      // The ping-pong this guards against: B stamps what it pulled with its
      // own clock, pushes it, A pulls it back, and the row churns forever.
      expect(remote.pushedRows, after);
    });

    test('simultaneous edits converge, and the later write wins', () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();

      // Both offline, both editing the same record.
      a.clock = 2000;
      b.clock = 3000;
      await a.subjects.update(_subject('s1', 'Physio (A)'));
      await b.subjects.update(_subject('s1', 'Physio (B)'));

      await a.syncNow();
      await b.syncNow();
      await a.syncNow();

      expect(a.subjects.getAll().single.name, b.subjects.getAll().single.name);
      expect(a.subjects.getAll().single.name, 'Physio (B)');
    });

    test('they converge whichever order they sync in', () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();

      a.clock = 3000;
      b.clock = 2000;
      await a.subjects.update(_subject('s1', 'Physio (A)'));
      await b.subjects.update(_subject('s1', 'Physio (B)'));

      // B first this time; A still holds the newer write.
      await b.syncNow();
      await a.syncNow();
      await b.syncNow();

      expect(a.subjects.getAll().single.name, b.subjects.getAll().single.name);
      expect(a.subjects.getAll().single.name, 'Physio (A)');
    });
  });

  group('deletes', () {
    test('a delete on one device removes it from the other', () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();
      expect(b.subjects.getAll(), hasLength(1));

      a.clock = 2000;
      await a.subjects.delete('s1');
      await a.syncNow();
      await b.syncNow();

      expect(b.subjects.getAll(), isEmpty);
      expect(b.boxes.subjects.get('s1')!.isDeleted, isTrue,
          reason: 'B keeps the tombstone, or it would resurrect the row');
    });

    test('a device that stayed offline does not resurrect a deleted record',
        () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();

      // A deletes and syncs while B is away.
      a.clock = 5000;
      await a.subjects.delete('s1');
      await a.syncNow();

      // B comes back holding its stale, un-edited copy.
      await b.syncNow();
      await a.syncNow();

      expect(b.subjects.getAll(), isEmpty);
      expect(a.subjects.getAll(), isEmpty,
          reason: 'B must not have pushed its live copy back over the delete');
    });

    test('a fresh install cannot push its emptiness over the other device',
        () async {
      final a = await device('a');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();

      // B has never held this record, so it has no tombstone for it —
      // absence is not a deletion.
      final b = await device('b');
      await b.syncNow();
      await a.syncNow();

      expect(a.subjects.getAll(), hasLength(1));
      expect(b.subjects.getAll(), hasLength(1));
    });
  });

  group('study logs', () {
    test('logs from both devices union rather than compete', () async {
      final a = await device('a');
      final b = await device('b');

      await a.logs.append(_log('study-s1-1', 'Physiology', 45));
      await b.logs.append(_log('study-s1-2', 'Anatomy', 30));

      await a.syncNow();
      await b.syncNow();
      await a.syncNow();

      // Deterministic ids and two devices that cannot run the same session
      // mean there is no conflict to resolve here, only a union.
      expect(a.logs.getAll().map((l) => l.id).toSet(),
          {'study-s1-1', 'study-s1-2'});
      expect(b.logs.getAll().map((l) => l.id).toSet(),
          {'study-s1-1', 'study-s1-2'});
    });
  });

  group('account switching', () {
    test('sync refuses when the device belongs to another account', () async {
      final a = await device('a');
      await a.metadata.setLastSyncedUserId('someone-else');
      await a.subjects.add(_subject('s1', 'Physiology'));

      await a.syncNow();

      expect(remote.pushedRows, 0,
          reason: 'one account\'s tasks must not land in another');
      expect(a.container.read(syncControllerProvider).blockedByAccountSwitch,
          isTrue);
    });

    test('adopting the account resumes sync', () async {
      final a = await device('a');
      await a.metadata.setLastSyncedUserId('someone-else');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();

      await a.sync.adoptCurrentAccount();

      expect(remote.pushedRows, 1);
      expect(a.container.read(syncControllerProvider).blockedByAccountSwitch,
          isFalse);
    });
  });
}

Subject _subject(String id, String name) =>
    Subject(id: id, name: name, colorValue: 0xFFD8A657,
        createdAt: DateTime(2026, 3, 2));

StudyLog _log(String id, String subject, int minutes) => StudyLog(
      id: id,
      subjectId: 's1',
      subjectName: subject,
      durationMinutes: minutes,
      timestamp: DateTime(2026, 9, 14, 20),
    );
