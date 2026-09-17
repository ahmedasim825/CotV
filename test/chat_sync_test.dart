// Chat history's half of sync: the v2 schema step, the soft deletes it
// exists for, and the sync surface the engine drives.
//
// Real in-memory SQLite throughout, per the idiom in chat_session_test —
// the migrations and the foreign key are the parts most worth testing, and
// a fake asserts nothing about either.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/repositories/chat_session_repository.dart';
import 'package:cotv/src/services/milo_sync_service.dart';
import 'package:cotv/src/services/sync_merge.dart';
import 'package:cotv/src/storage/app_database.dart';

void main() {
  late AppDatabase database;
  late SqliteChatSessionRepository repository;

  setUp(() {
    database = AppDatabase.openAt(':memory:');
    repository = SqliteChatSessionRepository(database);
  });

  tearDown(() {
    repository.dispose();
    database.dispose();
  });

  group('schema v2', () {
    test('upgrades a v1 database and backfills message timestamps', () {
      // A v1 database, built by hand: the columns as they were before soft
      // deletes, with user_version pinned so the migration walks forward.
      final db = sqlite3.openInMemory();
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('''
        CREATE TABLE chat_sessions (
          id TEXT PRIMARY KEY, title TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          sync_state TEXT NOT NULL DEFAULT 'pending_upload')
      ''');
      db.execute('''
        CREATE TABLE chat_messages (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL REFERENCES chat_sessions(id)
            ON DELETE CASCADE,
          role TEXT NOT NULL, content TEXT NOT NULL,
          timestamp INTEGER NOT NULL, tokens_used INTEGER,
          sync_state TEXT NOT NULL DEFAULT 'pending_upload')
      ''');
      db.execute(
        "INSERT INTO chat_sessions VALUES ('s1', 'Old', 100, 200, 'synced')",
      );
      db.execute(
        "INSERT INTO chat_messages "
        "VALUES ('m1', 's1', 'user', 'hello', 4242, NULL, 'synced')",
      );
      db.execute('PRAGMA user_version = 1');

      AppDatabase(db).migrateForTest();

      expect(
        db.select('PRAGMA user_version').first.values.first,
        AppDatabase.schemaVersion,
      );
      final message = db.select('SELECT * FROM chat_messages').first;
      expect(message['deleted'], 0);
      // A message has never been edited, so when it was written is when it
      // last changed — without the backfill every pre-v2 message would sort
      // as older than everything and lose to any remote row.
      expect(message['client_updated_at'], 4242);
      expect(db.select('SELECT * FROM chat_sessions').first['deleted'], 0);

      db.close();
    });

    test('SyncState no longer carries a deleted member', () {
      // Deleted-ness and pushed-ness are orthogonal: a deleted row still
      // has to be pushed, and until it has been it is both. Deletion lives
      // in its own column.
      expect(SyncState.values, [SyncState.synced, SyncState.pendingUpload]);
      // Nothing ever wrote the string, and an unknown value is forgiven
      // rather than thrown on.
      expect(SyncState.fromWire('deleted'), SyncState.pendingUpload);
    });
  });

  group('forgetting', () {
    test('clear tombstones rather than deletes', () async {
      final a = await repository.createSession(title: 'One');
      final b = await repository.createSession(title: 'Two');
      await repository.append(_message('m1', a.id));
      await repository.append(_message('m2', b.id));

      await repository.clear();

      expect(repository.listSessions(), isEmpty);
      // The one that matters most in this file. clear() is what
      // MiloConversation.forget() calls, so a hard delete here would have
      // the next pull quietly un-forget everything the user asked Milo to
      // forget.
      expect(repository.pendingSessions(), hasLength(2));
      expect(
        repository.pendingSessions().every((row) => row['deleted'] == 1),
        isTrue,
      );
      expect(repository.pendingMessages(), hasLength(2));
    });

    test('a tombstone carries a fresh timestamp', () async {
      final session = await repository.createSession(title: 'One');
      final before =
          repository.sessionRow(session.id)!['client_updated_at'] as int;

      await repository.deleteSession(session.id);

      // A tombstone that kept the thread's old timestamp would lose to the
      // live copy still sitting on the other device.
      expect(
        repository.sessionRow(session.id)!['client_updated_at'] as int,
        greaterThanOrEqualTo(before),
      );
    });
  });

  group('the sync surface', () {
    test('a fresh write is pending and goes clean once marked', () async {
      final session = await repository.createSession(title: 'One');
      await repository.append(_message('m1', session.id));

      expect(repository.pendingSessions().map((r) => r['id']), [session.id]);
      expect(repository.pendingMessages().map((r) => r['id']), ['m1']);

      repository.markSessionsSynced([session.id]);
      repository.markMessagesSynced(['m1']);

      expect(repository.pendingSessions(), isEmpty);
      expect(repository.pendingMessages(), isEmpty);
    });

    test('applyRemote writes a row clean, without touching its parent',
        () async {
      final session = await repository.createSession(title: 'One');
      repository.markSessionsSynced([session.id]);
      final parentBefore =
          repository.sessionRow(session.id)!['updated_at'] as int;

      repository.applyRemoteMessage({
        'id': 'm-remote',
        'session_id': session.id,
        'role': 'user',
        'content': 'from the phone',
        'timestamp': 9_999_999,
        'tokens_used': null,
        'client_updated_at': 9_999_999,
        'deleted': 0,
      });

      // Not `append`: that also bumps the parent and notifies per message,
      // both wrong for a pulled row.
      expect(repository.sessionRow(session.id)!['updated_at'], parentBefore);
      expect(repository.pendingMessages(), isEmpty,
          reason: 'a pulled row must not read as needing a push');
      expect(repository.messageCount(session.id), 1);
    });

    test('refreshSessionTimestamp follows the newest live message', () async {
      final session = await repository.createSession(title: 'One');
      for (final (id, at) in [('m1', 1000), ('m2', 5000)]) {
        repository.applyRemoteMessage({
          'id': id,
          'session_id': session.id,
          'role': 'user',
          'content': 'x',
          'timestamp': at,
          'tokens_used': null,
          'client_updated_at': at,
          'deleted': 0,
        });
      }

      repository.refreshSessionTimestamp(session.id);

      // A thread both devices appended to has a transcript neither side's
      // stored timestamp describes, so it is recomputed rather than merged.
      expect(repository.sessionRow(session.id)!['updated_at'], 5000);
    });

    test('a batch inside one transaction emits exactly one change', () async {
      final session = await repository.createSession(title: 'One');
      final seen = <int>[];
      final subscription =
          repository.watchSessions().listen((list) => seen.add(list.length));
      await Future<void>.delayed(Duration.zero);
      seen.clear();

      await repository.transaction(() async {
        for (var i = 0; i < 50; i++) {
          repository.applyRemoteMessage({
            'id': 'm$i',
            'session_id': session.id,
            'role': 'user',
            'content': 'x',
            'timestamp': 1000 + i,
            'tokens_used': null,
            'client_updated_at': 1000 + i,
            'deleted': 0,
          });
        }
      });
      await Future<void>.delayed(Duration.zero);

      // Applying a fifty-message thread outside a transaction would
      // re-query the session list fifty times and rebuild the drawer with
      // it. The repository already had the mechanism; sync uses it.
      expect(seen, hasLength(1));
      await subscription.cancel();
    });
  });

  group('row mapping', () {
    test('a session round-trips between SQLite and Postgres shapes', () async {
      final session = await repository.createSession(title: 'Cardiology');
      final local = repository.pendingSessions().single;

      final wire = chatSessionToRow(local);
      expect(wire['deleted'], isFalse, reason: 'bool on the wire, 0/1 local');
      expect(wire['client_updated_at'], local['client_updated_at']);

      final back = chatSessionFromRow({
        ...wire,
        'updated_at': '2026-09-17T05:00:00Z',
      });
      expect(back['id'], session.id);
      expect(back['title'], 'Cardiology');
      expect(back['created_at'], local['created_at']);
      expect(back['deleted'], 0);
    });

    test('a tombstoned message round-trips as deleted', () async {
      final session = await repository.createSession();
      await repository.append(_message('m1', session.id));
      await repository.deleteSession(session.id);

      final wire = chatMessageToRow(repository.pendingMessages().single);
      expect(wire['deleted'], isTrue);

      final back = chatMessageFromRow({
        ...wire,
        'updated_at': '2026-09-17T05:00:00Z',
      });
      expect(back['deleted'], 1);
    });
  });

  group('resolveChatRow', () {
    Map<String, Object?> row(int millis, {String state = 'synced'}) =>
        {'client_updated_at': millis, 'sync_state': state};

    test('no local row takes the remote', () {
      expect(
        resolveChatRow(local: null, remote: {'client_updated_at': 1}),
        MergeDecision.applyRemote,
      );
    });

    test('a clean local row yields, and matches when identical', () {
      expect(
        resolveChatRow(local: row(9000), remote: {'client_updated_at': 1000}),
        MergeDecision.applyRemote,
      );
      expect(
        resolveChatRow(local: row(1000), remote: {'client_updated_at': 1000}),
        MergeDecision.inSync,
      );
    });

    test('a pending row is a conflict, settled on the clock', () {
      expect(
        resolveChatRow(
          local: row(1000, state: 'pending_upload'),
          remote: {'client_updated_at': 2000},
        ),
        MergeDecision.applyRemote,
      );
      expect(
        resolveChatRow(
          local: row(2000, state: 'pending_upload'),
          remote: {'client_updated_at': 1000},
        ),
        MergeDecision.keepLocal,
      );
      // A tie takes the remote, so both devices land on the same answer.
      expect(
        resolveChatRow(
          local: row(1000, state: 'pending_upload'),
          remote: {'client_updated_at': 1000},
        ),
        MergeDecision.applyRemote,
      );
    });
  });
}

ChatMessage _message(String id, String sessionId) => ChatMessage(
      id: id,
      sessionId: sessionId,
      isUser: true,
      text: 'hello',
      timestamp: DateTime.utc(2026, 9, 14, 20),
    );
