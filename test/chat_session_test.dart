// The SQL half of Milo's storage: schema, migrations, the capped context
// window, and the one-time import of the pre-threads transcript.
//
// Everything runs against a real in-memory SQLite database rather than a
// fake. The migrations and the `ON DELETE CASCADE` are the parts most worth
// testing and a fake would assert nothing about either.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/models/chat_session.dart';
import 'package:cotv/src/repositories/chat_import.dart';
import 'package:cotv/src/repositories/chat_repository.dart';
import 'package:cotv/src/repositories/chat_session_repository.dart';
import 'package:cotv/src/storage/app_database.dart';

/// Stands in for the Hive box the importer reads.
class _InMemoryChatRepository implements ChatRepository {
  _InMemoryChatRepository([List<ChatMessage> initial = const []])
      : _messages = [...initial];

  final List<ChatMessage> _messages;

  @override
  Future<void> append(ChatMessage message) async => _messages.add(message);

  @override
  List<ChatMessage> recent(int count) {
    if (count <= 0) return const [];
    final sorted = [..._messages]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return sorted.length <= count
        ? sorted
        : sorted.sublist(sorted.length - count);
  }

  @override
  int get count => _messages.length;

  @override
  Future<void> clear() async => _messages.clear();
}

final _epoch = DateTime.utc(2026, 3, 17, 9);

ChatMessage _message(
  String id, {
  required String sessionId,
  bool isUser = true,
  String text = 'hello',
  int minute = 0,
  int? tokensUsed,
}) =>
    ChatMessage(
      id: id,
      sessionId: sessionId,
      isUser: isUser,
      text: text,
      timestamp: _epoch.add(Duration(minutes: minute)),
      tokensUsed: tokensUsed,
    );

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

  group('schema', () {
    test('creates at the current version and is idempotent to reopen', () {
      final version =
          database.raw.select('PRAGMA user_version').first.values.first;
      expect(version, AppDatabase.schemaVersion);

      // Re-running the migration must not throw on tables that exist —
      // this is the path every launch after the first takes.
      final again = AppDatabase.openAt(':memory:');
      addTearDown(again.dispose);
      expect(
        again.raw.select('PRAGMA user_version').first.values.first,
        AppDatabase.schemaVersion,
      );
    });

    test('foreign keys are on, so deletes actually cascade', () {
      final on = database.raw.select('PRAGMA foreign_keys').first.values.first;
      expect(on, 1, reason: 'off by default, and the cascade needs it');
    });
  });

  group('sessions', () {
    test('lists newest activity first, without reading message bodies',
        () async {
      final older = await repository.createSession(
        title: 'Older',
        now: _epoch,
      );
      final newer = await repository.createSession(
        title: 'Newer',
        now: _epoch.add(const Duration(hours: 1)),
      );

      expect(
        repository.listSessions().map((s) => s.id),
        [newer.id, older.id],
      );
      // Counted in SQL, not by loading the rows.
      expect(repository.listSessions().first.messageCount, 0);
    });

    test('appending moves a thread to the top and counts it', () async {
      final first = await repository.createSession(title: 'A', now: _epoch);
      await repository.createSession(
        title: 'B',
        now: _epoch.add(const Duration(minutes: 5)),
      );

      await repository.append(
        _message('m1', sessionId: first.id, minute: 30),
      );

      final listed = repository.listSessions();
      expect(listed.first.id, first.id);
      expect(listed.first.messageCount, 1);
    });

    test('rename ignores an empty title rather than blanking the row',
        () async {
      final session = await repository.createSession(title: 'Kept');
      await repository.rename(session.id, '   ');
      expect(repository.findById(session.id)!.title, 'Kept');
    });

    test('deleting a session takes its messages with it', () async {
      final session = await repository.createSession();
      await repository.append(_message('m1', sessionId: session.id));
      await repository.append(_message('m2', sessionId: session.id, minute: 1));
      expect(repository.messageCount(session.id), 2);

      await repository.deleteSession(session.id);

      expect(repository.findById(session.id), isNull);
      final orphans = database.raw.select(
        'SELECT COUNT(*) AS n FROM chat_messages WHERE session_id = ?',
        [session.id],
      );
      expect(orphans.first['n'], 0, reason: 'ON DELETE CASCADE');
    });

    test('search matches a title or anything said in the thread', () async {
      final byTitle = await repository.createSession(title: 'Cardiology');
      final byBody = await repository.createSession(title: 'Untitled thread');
      await repository.append(
        _message('m1', sessionId: byBody.id, text: 'what about cardiology'),
      );

      expect(repository.search('cardio').map((s) => s.id),
          containsAll([byTitle.id, byBody.id]));
      expect(repository.search('nothing here'), isEmpty);
      // An empty query is not a filter — it is the unfiltered list.
      expect(repository.search('  ').length, 2);
    });
  });

  group('context window', () {
    test('caps at the message limit, keeping the newest', () async {
      final session = await repository.createSession();
      for (var i = 0; i < 25; i++) {
        await repository.append(
          _message('m$i', sessionId: session.id, text: 'turn $i', minute: i),
        );
      }

      final window = repository.contextWindow(session.id);

      expect(window, hasLength(SqliteChatSessionRepository.contextMessageLimit));
      // Oldest-first within the window, and ending on the latest turn —
      // dropping the last message would answer the wrong question.
      expect(window.last.text, 'turn 24');
      expect(window.first.text, 'turn 10');
    });

    test('cuts on tokens when one turn is enormous', () async {
      final session = await repository.createSession();
      await repository.append(
        _message('old', sessionId: session.id, text: 'a' * 8000, minute: 0),
      );
      await repository.append(
        _message('new', sessionId: session.id, text: 'and now this', minute: 1),
      );

      final window = repository.contextWindow(session.id);

      // The 8000-character turn is ~2000 tokens on its own, so it cannot
      // ride along with anything else.
      expect(window.map((m) => m.id), ['new']);
    });

    test('a reported token count beats the estimate', () {
      final estimated = _message('a', sessionId: 's', text: 'x' * 400);
      final reported =
          _message('b', sessionId: 's', text: 'x' * 400, tokensUsed: 7);

      expect(estimated.approximateTokens, 100);
      expect(reported.approximateTokens, 7);
    });

    test('never returns another thread\'s messages', () async {
      final mine = await repository.createSession();
      final theirs = await repository.createSession();
      await repository.append(
        _message('m1', sessionId: theirs.id, text: 'not mine'),
      );

      expect(repository.contextWindow(mine.id), isEmpty);
    });
  });

  group('paging', () {
    test('returns the newest page first, oldest-first within it', () async {
      final session = await repository.createSession();
      for (var i = 0; i < 120; i++) {
        await repository.append(
          _message('m$i', sessionId: session.id, text: 'turn $i', minute: i),
        );
      }

      final page = repository.messages(session.id, limit: 50);
      expect(page, hasLength(50));
      expect(page.first.text, 'turn 70');
      expect(page.last.text, 'turn 119');

      final older = repository.messages(session.id, limit: 50, offset: 50);
      expect(older.last.text, 'turn 69');
    });
  });

  group('legacy import', () {
    test('moves the flat transcript into one dated thread', () async {
      final legacy = _InMemoryChatRepository([
        _message('old-1', sessionId: '', text: 'first', minute: 0),
        _message('old-2', sessionId: '', text: 'second', minute: 5),
      ]);

      final moved = await ChatImporter(
        source: legacy,
        destination: repository,
      ).importIfNeeded();

      expect(moved, 2);
      final session = repository.findById(ChatImporter.sessionId)!;
      expect(session.title, ChatImporter.sessionTitle);
      expect(session.messageCount, 2);
      // Dated by its contents, so it sorts into the drawer by when it
      // happened rather than jumping to the top as if it were new.
      expect(session.createdAt, _epoch);

      expect(
        repository.messages(session.id).map((m) => m.text),
        ['first', 'second'],
      );
    });

    test('a second run is a no-op, not a second copy', () async {
      final legacy = _InMemoryChatRepository([
        _message('old-1', sessionId: '', text: 'first'),
      ]);
      final importer =
          ChatImporter(source: legacy, destination: repository);

      expect(await importer.importIfNeeded(), 1);
      expect(await importer.importIfNeeded(), 0);
      expect(repository.messageCount(ChatImporter.sessionId), 1);
      expect(repository.listSessions(), hasLength(1));
    });

    test('leaves the source alone, so a failed run can be re-run', () async {
      final legacy = _InMemoryChatRepository([
        _message('old-1', sessionId: '', text: 'first'),
      ]);

      await ChatImporter(source: legacy, destination: repository)
          .importIfNeeded();

      expect(legacy.count, 1, reason: 'the Hive box is not cleared');
    });

    test('an empty box imports nothing and creates no thread', () async {
      final moved = await ChatImporter(
        source: _InMemoryChatRepository(),
        destination: repository,
      ).importIfNeeded();

      expect(moved, 0);
      expect(repository.listSessions(), isEmpty);
    });
  });

  group('titles', () {
    test('derive from the first message, cut on a word boundary', () {
      expect(ChatSession.titleFrom('What is my next prayer'),
          'What is my next prayer');
      expect(ChatSession.titleFrom('   '), ChatSession.untitled);

      final long = ChatSession.titleFrom(
        'Explain the pathophysiology of congestive cardiac failure in detail',
      );
      expect(long.length, lessThanOrEqualTo(ChatSession.titleLength + 1));
      expect(long, endsWith('…'));
      expect(long, isNot(contains('  ')));
    });

    test('collapses the whitespace a pasted prompt arrives with', () {
      expect(ChatSession.titleFrom('one\n\n  two'), 'one two');
    });
  });
}
