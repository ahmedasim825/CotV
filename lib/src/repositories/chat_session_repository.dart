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

/// The chat store as the sync engine sees it.
///
/// Rows rather than models, unlike the Hive entities' [SyncableRepository].
/// A session's sync columns are not on [ChatSession] and a message's are
/// not on [ChatMessage] — adding them would put sync metadata on a Hive
/// model that only the legacy box still uses. Chat is SQL, so the seam is
/// SQL-shaped.
abstract class ChatSyncRepository {
  /// Session rows the server has not seen, tombstones included.
  List<Map<String, Object?>> pendingSessions();

  List<Map<String, Object?>> pendingMessages();

  Map<String, Object?>? sessionRow(String id);

  Map<String, Object?>? messageRow(String id);

  /// Writes a row exactly as it arrived and marks it synced, without
  /// touching the parent session or emitting a change of its own.
  ///
  /// Callers apply a whole pull batch inside [transaction], which notifies
  /// once at COMMIT — otherwise a fifty-message thread would re-query the
  /// session list fifty times.
  void applyRemoteSession(Map<String, Object?> row);

  void applyRemoteMessage(Map<String, Object?> row);

  void markSessionsSynced(Iterable<String> ids);

  void markMessagesSynced(Iterable<String> ids);

  /// Recomputes a session's `updated_at` from its newest live message.
  ///
  /// Self-healing, and correct when both devices appended to the same
  /// thread: neither side's stored value describes the merged transcript.
  void refreshSessionTimestamp(String id);
}

class SqliteChatSessionRepository
    implements ChatSessionRepository, ChatSyncRepository {
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
      and: 'AND (LOWER(s.title) LIKE ? '
          'OR EXISTS (SELECT 1 FROM chat_messages m2 '
          'WHERE m2.session_id = s.id AND m2.deleted = 0 '
          'AND LOWER(m2.content) LIKE ?))',
      parameters: [like, like],
    );
  }

  /// [and] is an AND-fragment, not a whole WHERE clause: the tombstone
  /// filter is not optional, so it belongs in the base query where no
  /// caller can forget it.
  List<ChatSession> _sessionsWhere({
    String and = '',
    List<Object?> parameters = const [],
  }) {
    final rows = _db.select(
      'SELECT s.id, s.title, s.created_at, s.updated_at, '
      '(SELECT COUNT(*) FROM chat_messages m '
      'WHERE m.session_id = s.id AND m.deleted = 0) AS message_count '
      'FROM chat_sessions s WHERE s.deleted = 0 $and '
      'ORDER BY s.updated_at DESC',
      parameters,
    );

    return List.unmodifiable(rows.map(_sessionFrom));
  }

  @override
  ChatSession? findById(String id) {
    final rows = _db.select(
      'SELECT s.id, s.title, s.created_at, s.updated_at, '
      '(SELECT COUNT(*) FROM chat_messages m '
      'WHERE m.session_id = s.id AND m.deleted = 0) AS message_count '
      'FROM chat_sessions s WHERE s.id = ? AND s.deleted = 0',
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
      'updated_at, sync_state, client_updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        session.id,
        session.title,
        session.createdAt.millisecondsSinceEpoch,
        session.updatedAt.millisecondsSinceEpoch,
        SyncState.pendingUpload.wire,
        session.updatedAt.millisecondsSinceEpoch,
      ],
    );
    _notify();
    return session;
  }

  @override
  Future<void> rename(String id, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    // `updated_at` is deliberately left alone — it is what the drawer
    // orders by, and a rename is not new activity. `client_updated_at` does
    // move, because it is what sync compares: without that the renamed
    // thread would tie with the server's copy and never win.
    _db.execute(
      'UPDATE chat_sessions SET title = ?, sync_state = ?, '
      'client_updated_at = ? WHERE id = ?',
      [
        clean,
        SyncState.pendingUpload.wire,
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
    _notify();
  }

  @override
  Future<void> deleteSession(String id) async {
    // ON DELETE CASCADE used to do the messages. Nothing is deleted now, so
    // the cascade never fires and they have to be tombstoned by hand — in
    // the same transaction as the session, because live orphan messages
    // still match `search`, and the thread would come back as a search
    // result for a conversation the user deleted.
    _db.execute('BEGIN');
    try {
      _tombstoneSessions('WHERE id = ?', [id]);
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
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
      'FROM chat_messages WHERE session_id = ? AND deleted = 0 '
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
      'timestamp, tokens_used, sync_state, client_updated_at, deleted) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)',
      [
        message.id,
        message.sessionId,
        message.role,
        message.text,
        message.timestamp.millisecondsSinceEpoch,
        message.tokensUsed,
        SyncState.pendingUpload.wire,
        message.timestamp.millisecondsSinceEpoch,
      ],
    );

    // The thread's own timestamp follows its last message, which is what
    // the drawer orders by. Done in the same call rather than left to the
    // caller so a write cannot leave the list stale.
    _db.execute(
      'UPDATE chat_sessions SET updated_at = ?, sync_state = ?, '
      'client_updated_at = ? WHERE id = ?',
      [
        message.timestamp.millisecondsSinceEpoch,
        SyncState.pendingUpload.wire,
        message.timestamp.millisecondsSinceEpoch,
        message.sessionId,
      ],
    );
    _notify();
  }

  @override
  int messageCount(String sessionId) {
    final rows = _db.select(
      'SELECT COUNT(*) AS n FROM chat_messages '
      'WHERE session_id = ? AND deleted = 0',
      [sessionId],
    );
    return rows.first['n'] as int;
  }

  /// Marks every session matching [where] deleted, and its messages with
  /// it. Caller supplies the transaction.
  ///
  /// `updated_at` moves too: it is what the other device compares, and a
  /// tombstone that kept the deleted thread's old timestamp would lose to
  /// the live copy still sitting on the other device.
  void _tombstoneSessions(String where, List<Object?> parameters) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      'UPDATE chat_messages SET deleted = 1, client_updated_at = ?, '
      'sync_state = ? '
      'WHERE session_id IN (SELECT id FROM chat_sessions $where)',
      [now, SyncState.pendingUpload.wire, ...parameters],
    );
    _db.execute(
      'UPDATE chat_sessions SET deleted = 1, client_updated_at = ?, '
      'sync_state = ? $where',
      [now, SyncState.pendingUpload.wire, ...parameters],
    );
  }

  @override
  Future<void> clear() async {
    // Tombstones rather than deletes, and this is the case where getting it
    // wrong is worst: `clear()` is what MiloConversation.forget() calls, so
    // a hard delete here would have the next pull quietly un-forget
    // everything the user asked Milo to forget.
    _db.execute('BEGIN');
    try {
      _tombstoneSessions('', const []);
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
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

  // ---------------------------------------------------------------------
  // ChatSyncRepository
  // ---------------------------------------------------------------------

  static const String _sessionColumns =
      'id, title, created_at, updated_at, client_updated_at, deleted';
  static const String _messageColumns =
      'id, session_id, role, content, timestamp, tokens_used, '
      'client_updated_at, deleted';

  @override
  List<Map<String, Object?>> pendingSessions() => _rows(
        'SELECT $_sessionColumns FROM chat_sessions WHERE sync_state = ?',
        [SyncState.pendingUpload.wire],
      );

  @override
  List<Map<String, Object?>> pendingMessages() => _rows(
        'SELECT $_messageColumns FROM chat_messages WHERE sync_state = ?',
        [SyncState.pendingUpload.wire],
      );

  @override
  Map<String, Object?>? sessionRow(String id) {
    final rows = _rows(
      'SELECT $_sessionColumns, sync_state FROM chat_sessions WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Map<String, Object?>? messageRow(String id) {
    final rows = _rows(
      'SELECT $_messageColumns, sync_state FROM chat_messages WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  @override
  void applyRemoteSession(Map<String, Object?> row) {
    // ON CONFLICT DO UPDATE, emphatically not INSERT OR REPLACE. REPLACE
    // deletes the conflicting row before re-inserting it, which fires
    // chat_messages' ON DELETE CASCADE and silently takes the whole
    // transcript with it — a thread the other device merely renamed would
    // come back empty.
    _db.execute(
      'INSERT INTO chat_sessions '
      '(id, title, created_at, updated_at, sync_state, client_updated_at, '
      'deleted) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'title = excluded.title, sync_state = excluded.sync_state, '
      'client_updated_at = excluded.client_updated_at, '
      'deleted = excluded.deleted',
      [
        row['id'],
        row['title'],
        row['created_at'],
        // Activity order is recomputed from the merged transcript by
        // refreshSessionTimestamp, so an inserted row just needs a
        // plausible starting value.
        row['client_updated_at'],
        SyncState.synced.wire,
        row['client_updated_at'],
        row['deleted'],
      ],
    );
  }

  @override
  void applyRemoteMessage(Map<String, Object?> row) {
    // Not `append`: that also bumps the parent session and notifies per
    // message, both of which are wrong for a pulled row.
    _db.execute(
      'INSERT INTO chat_messages '
      '(id, session_id, role, content, timestamp, tokens_used, sync_state, '
      'client_updated_at, deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'content = excluded.content, sync_state = excluded.sync_state, '
      'client_updated_at = excluded.client_updated_at, '
      'deleted = excluded.deleted',
      [
        row['id'],
        row['session_id'],
        row['role'],
        row['content'],
        row['timestamp'],
        row['tokens_used'],
        SyncState.synced.wire,
        row['client_updated_at'],
        row['deleted'],
      ],
    );
  }

  @override
  void markSessionsSynced(Iterable<String> ids) =>
      _markSynced('chat_sessions', ids);

  @override
  void markMessagesSynced(Iterable<String> ids) =>
      _markSynced('chat_messages', ids);

  void _markSynced(String table, Iterable<String> ids) {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    final slots = List.filled(list.length, '?').join(', ');
    _db.execute(
      'UPDATE $table SET sync_state = ? WHERE id IN ($slots)',
      [SyncState.synced.wire, ...list],
    );
  }

  @override
  void refreshSessionTimestamp(String id) {
    _db.execute(
      'UPDATE chat_sessions SET updated_at = COALESCE('
      '(SELECT MAX(timestamp) FROM chat_messages '
      ' WHERE session_id = ? AND deleted = 0), updated_at) '
      'WHERE id = ? AND deleted = 0',
      [id, id],
    );
  }

  List<Map<String, Object?>> _rows(String sql, List<Object?> parameters) =>
      _db.select(sql, parameters).map((row) => {...row}).toList(growable: false);

  void dispose() => _changes.close();
}
