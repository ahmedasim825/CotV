import 'dart:async';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../storage/app_database.dart';

/// Threads, and the messages in them.
///
/// Every read here is a query with a `LIMIT`, which is the reason this is
/// SQL rather than another Hive box. Listing the drawer reads titles and a
/// count and never touches a message body; opening a thread reads one page;
/// the model's context window reads fifteen rows. Idle, nothing is held but
/// the connection.
///
/// Change notification is a broadcast controller rather than a database
/// hook: SQLite has no built-in change stream, and every write in the app
/// goes through this class, so signalling from here cannot miss one.
abstract class ChatSessionRepository {
  /// Session metadata, newest activity first. Never includes messages.
  Stream<List<ChatSession>> watchSessions();

  List<ChatSession> listSessions();

  /// Sessions whose title or message text matches [query].
  List<ChatSession> search(String query);

  ChatSession? findById(String id);

  Future<ChatSession> createSession({String? title, DateTime? now});

  /// Inserts a session under an id the caller chose.
  ///
  /// Exists for the legacy import, which needs a fixed id so re-running it
  /// is a no-op. Ordinary callers use [createSession] and let the
  /// repository mint the id — two sessions sharing one is a worse failure
  /// than a slightly wider interface.
  Future<ChatSession> insertSession(ChatSession session);

  Future<void> rename(String id, String title);

  /// Removes the session and, by cascade, every message in it.
  Future<void> deleteSession(String id);

  /// One page of a thread, oldest first within the page.
  List<ChatMessage> messages(String sessionId, {int limit, int offset});

  /// The tail of a thread, capped for a model's context window.
  List<ChatMessage> contextWindow(String sessionId);

  Future<void> append(ChatMessage message);

  /// How many messages the thread holds.
  int messageCount(String sessionId);

  Future<void> clear();

  /// Runs [action] as one transaction, rolling back if it throws.
  ///
  /// The import needs it: a session inserted without its messages looks
  /// exactly like a completed import to the next run, so the two writes
  /// have to succeed or fail together.
  Future<T> transaction<T>(Future<T> Function() action);
}

class SqliteChatSessionRepository implements ChatSessionRepository {
  SqliteChatSessionRepository(this._database);

  /// The rolling window handed to a model.
  ///
  /// Fifteen messages or ~2000 tokens, whichever binds first. The message
  /// count is what usually binds and is the cheaper check; the token
  /// ceiling exists for the thread where someone pasted a stack trace.
  static const int contextMessageLimit = 15;
  static const int contextTokenLimit = 2000;

  /// One page of a transcript. The panel renders newest-first and pages
  /// backwards, so this is what a scroll to the top costs.
  static const int pageSize = 50;

  static const _uuid = Uuid();

  final AppDatabase _database;
  final _changes = StreamController<List<ChatSession>>.broadcast();

  Database get _db => _database.raw;

  @override
  Stream<List<ChatSession>> watchSessions() async* {
    yield listSessions();
    yield* _changes.stream;
  }

  void _notify() {
    if (_changes.hasListener) _changes.add(listSessions());
  }

  @override
  List<ChatSession> listSessions() => _sessionsWhere();

  @override
  List<ChatSession> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return listSessions();

    // Matches the title or anything said in the thread, so searching for a
    // word you remember using finds the conversation even when the title
    // came from a different sentence.
    final like = '%${trimmed.toLowerCase()}%';
    return _sessionsWhere(
      where: 'WHERE LOWER(s.title) LIKE ? '
          'OR EXISTS (SELECT 1 FROM chat_messages m2 '
          'WHERE m2.session_id = s.id AND LOWER(m2.content) LIKE ?)',
      parameters: [like, like],
    );
  }

  List<ChatSession> _sessionsWhere({
    String where = '',
    List<Object?> parameters = const [],
  }) {
    final rows = _db.select(
      'SELECT s.id, s.title, s.created_at, s.updated_at, '
      '(SELECT COUNT(*) FROM chat_messages m WHERE m.session_id = s.id) '
      'AS message_count '
      'FROM chat_sessions s $where ORDER BY s.updated_at DESC',
      parameters,
    );

    return List.unmodifiable(rows.map(_sessionFrom));
  }

  @override
  ChatSession? findById(String id) {
    final rows = _db.select(
      'SELECT s.id, s.title, s.created_at, s.updated_at, '
      '(SELECT COUNT(*) FROM chat_messages m WHERE m.session_id = s.id) '
      'AS message_count '
      'FROM chat_sessions s WHERE s.id = ?',
      [id],
    );
    return rows.isEmpty ? null : _sessionFrom(rows.first);
  }

  static ChatSession _sessionFrom(Row row) => ChatSession(
        id: row['id'] as String,
        title: row['title'] as String,
        // Read back as UTC, not local. The instant is the same either way,
        // but sync resolves collisions by comparing these, and a value that
        // changes meaning when the device moves timezone is not one to
        // compare. The UI calls toLocal() where it formats.
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at'] as int,
          isUtc: true,
        ),
        messageCount: row['message_count'] as int? ?? 0,
      );

  @override
  Future<ChatSession> createSession({String? title, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final session = ChatSession(
      // Time prefix so the id sorts the way the row does, and a uuid tail
      // because the clock alone does not make it unique: two sessions
      // created inside the same microsecond collided, and INSERT OR REPLACE
      // turned that collision into silent data loss rather than an error.
      id: 'chat-${at.microsecondsSinceEpoch}-${_uuid.v4().substring(0, 8)}',
      title: title ?? ChatSession.untitled,
      createdAt: at,
      updatedAt: at,
    );

    return insertSession(session);
  }

  @override
  Future<ChatSession> insertSession(ChatSession session) async {
    // A plain INSERT, so a duplicate id raises instead of overwriting the
    // thread that already holds it.
    _db.execute(
      'INSERT INTO chat_sessions (id, title, created_at, '
      'updated_at, sync_state) VALUES (?, ?, ?, ?, ?)',
      [
        session.id,
        session.title,
        session.createdAt.millisecondsSinceEpoch,
        session.updatedAt.millisecondsSinceEpoch,
        SyncState.pendingUpload.wire,
      ],
    );
    _notify();
    return session;
  }

  @override
  Future<void> rename(String id, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    _db.execute(
      'UPDATE chat_sessions SET title = ?, sync_state = ? WHERE id = ?',
      [clean, SyncState.pendingUpload.wire, id],
    );
    _notify();
  }

  @override
  Future<void> deleteSession(String id) async {
    // The messages go with it through ON DELETE CASCADE, which only fires
    // because AppDatabase turns foreign keys on per connection.
    _db.execute('DELETE FROM chat_sessions WHERE id = ?', [id]);
    _notify();
  }

  @override
  List<ChatMessage> messages(
    String sessionId, {
    int limit = pageSize,
    int offset = 0,
  }) {
    // Newest-first in SQL so a page is the *latest* page, then reversed so
    // the caller reads it oldest-first like any other transcript.
    final rows = _db.select(
      'SELECT id, session_id, role, content, timestamp, tokens_used '
      'FROM chat_messages WHERE session_id = ? '
      'ORDER BY timestamp DESC LIMIT ? OFFSET ?',
      [sessionId, limit, offset],
    );

    return List.unmodifiable(rows.map(_messageFrom).toList().reversed);
  }

  @override
  List<ChatMessage> contextWindow(String sessionId) {
    final recent = messages(sessionId, limit: contextMessageLimit);

    // Walk back from the newest, keeping what fits. Dropping from the front
    // rather than the back matters: the last thing said is the thing being
    // answered, and a window that drops it answers the wrong question.
    var tokens = 0;
    final kept = <ChatMessage>[];
    for (final message in recent.reversed) {
      tokens += message.approximateTokens;
      if (tokens > contextTokenLimit && kept.isNotEmpty) break;
      kept.add(message);
    }
    return List.unmodifiable(kept.reversed);
  }

  static ChatMessage _messageFrom(Row row) => ChatMessage(
        id: row['id'] as String,
        sessionId: row['session_id'] as String,
        isUser: row['role'] as String == 'user',
        text: row['content'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          row['timestamp'] as int,
          isUtc: true,
        ),
        tokensUsed: row['tokens_used'] as int?,
      );

  @override
  Future<void> append(ChatMessage message) async {
    _db.execute(
      'INSERT OR REPLACE INTO chat_messages (id, session_id, role, content, '
      'timestamp, tokens_used, sync_state) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        message.id,
        message.sessionId,
        message.role,
        message.text,
        message.timestamp.millisecondsSinceEpoch,
        message.tokensUsed,
        SyncState.pendingUpload.wire,
      ],
    );

    // The thread's own timestamp follows its last message, which is what
    // the drawer orders by. Done in the same call rather than left to the
    // caller so a write cannot leave the list stale.
    _db.execute(
      'UPDATE chat_sessions SET updated_at = ?, sync_state = ? WHERE id = ?',
      [
        message.timestamp.millisecondsSinceEpoch,
        SyncState.pendingUpload.wire,
        message.sessionId,
      ],
    );
    _notify();
  }

  @override
  int messageCount(String sessionId) {
    final rows = _db.select(
      'SELECT COUNT(*) AS n FROM chat_messages WHERE session_id = ?',
      [sessionId],
    );
    return rows.first['n'] as int;
  }

  @override
  Future<void> clear() async {
    _db.execute('DELETE FROM chat_sessions');
    _notify();
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    _db.execute('BEGIN');
    try {
      final result = await action();
      _db.execute('COMMIT');
      _notify();
      return result;
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void dispose() => _changes.close();
}
