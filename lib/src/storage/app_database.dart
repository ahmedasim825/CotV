import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// The SQL half of Milo's local storage.
///
/// Hive still owns tasks, habits, subjects, study logs and settings, and is
/// a good fit for them: whole-object reads of small collections. This
/// exists for the things it is a bad fit for — an ordered, paged message
/// history, and later a vector index and a sync queue. Those want `LIMIT`,
/// `ORDER BY` and a predicate, and doing them over `box.values` means
/// pulling the whole box into memory to throw most of it away.
///
/// Local-first is not a slogan here: this is the primary read and write
/// target. Sync, when it arrives, reconciles against it rather than the
/// other way round.
class AppDatabase {
  AppDatabase(this._db);

  /// Bumped whenever [_migrate] gains a step.
  static const int schemaVersion = 1;

  static const String fileName = 'milo.db';

  final Database _db;

  Database get raw => _db;

  /// Opens the on-disk database beside Hive's boxes.
  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return AppDatabase.openAt('${dir.path}/$fileName');
  }

  /// Opens [path], or an in-memory database when [path] is `:memory:`.
  ///
  /// Separate from [open] so tests get a real database with the real
  /// schema without a temp directory or a plugin — the migrations are the
  /// part most worth testing, and they are identical either way.
  static AppDatabase openAt(String path) {
    final db = path == ':memory:'
        ? sqlite3.openInMemory()
        : sqlite3.open(path);

    // Off by default in SQLite, and the whole reason `ON DELETE CASCADE`
    // on chat_messages does anything. Set per connection, not per database.
    db.execute('PRAGMA foreign_keys = ON');
    // Readers do not block the writer. The UI reads this database on every
    // frame that renders a message list.
    db.execute('PRAGMA journal_mode = WAL');

    final database = AppDatabase(db);
    database._migrate();
    return database;
  }

  /// Brings the schema up to [schemaVersion].
  ///
  /// Driven by SQLite's own `user_version` rather than a table of our own,
  /// so the version cannot disagree with the schema it describes. Each step
  /// is guarded by the version it upgrades *from*, so a database at any
  /// older version walks forward through every step in order.
  void _migrate() {
    final current = _db.select('PRAGMA user_version').first.values.first as int;
    if (current >= schemaVersion) return;

    _db.execute('BEGIN');
    try {
      if (current < 1) _createV1();
      _db.execute('PRAGMA user_version = $schemaVersion');
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _createV1() {
    // sync_state and updated_at exist from the first version even though
    // nothing reads them until the sync engine lands. Adding them later
    // would mean an ALTER over live rows; empty they cost a few bytes.
    _db.execute('''
      CREATE TABLE chat_sessions (
        id          TEXT    PRIMARY KEY,
        title       TEXT    NOT NULL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        sync_state  TEXT    NOT NULL DEFAULT 'pending_upload'
      )
    ''');

    _db.execute('''
      CREATE TABLE chat_messages (
        id          TEXT    PRIMARY KEY,
        session_id  TEXT    NOT NULL
                            REFERENCES chat_sessions(id) ON DELETE CASCADE,
        role        TEXT    NOT NULL,
        content     TEXT    NOT NULL,
        timestamp   INTEGER NOT NULL,
        tokens_used INTEGER,
        sync_state  TEXT    NOT NULL DEFAULT 'pending_upload'
      )
    ''');

    // Every message query is "this session, in time order" — the context
    // window, the paged transcript and the delete cascade alike.
    _db.execute(
      'CREATE INDEX idx_messages_session '
      'ON chat_messages(session_id, timestamp)',
    );

    // The drawer lists sessions most-recently-touched first.
    _db.execute(
      'CREATE INDEX idx_sessions_updated ON chat_sessions(updated_at DESC)',
    );
  }

  void dispose() => _db.close();
}

/// Where a row has got to on its way to the server.
///
/// Written from the first version so the sync engine has something to
/// select on when it arrives. Until then every row is born
/// [SyncState.pendingUpload] and nothing reads it.
enum SyncState {
  synced,
  pendingUpload,
  deleted;

  /// The stored form. Snake case because it is a database value and will
  /// be compared against one written by another client.
  String get wire {
    switch (this) {
      case SyncState.synced:
        return 'synced';
      case SyncState.pendingUpload:
        return 'pending_upload';
      case SyncState.deleted:
        return 'deleted';
    }
  }

  /// Unknown values read as [SyncState.pendingUpload] rather than throwing:
  /// a row written by a newer build is a row that still needs sending, and
  /// refusing to load the history over it would be worse.
  static SyncState fromWire(String? value) {
    for (final state in values) {
      if (state.wire == value) return state;
    }
    return SyncState.pendingUpload;
  }
}
