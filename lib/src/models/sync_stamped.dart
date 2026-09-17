/// The record metadata every synced entity carries.
///
/// Implemented by [Task], [Habit], [Subject], [StudyLog] and [UserSettings]
/// so the merge and engine code can read a record's sync state without
/// knowing which box it came out of. The stamping methods are deliberately
/// *not* here: each returns its own concrete type, and a self-referential
/// generic buys nothing when the only callers — the repositories — already
/// know the type they hold.
///
/// ## Why milliseconds rather than DateTime
///
/// `hive_ce` registers `DateTimeWithTimezoneAdapter` ahead of
/// `DateTimeAdapter<DateTimeWithoutTZ>`, and `findAdapterForValue` returns
/// on the first runtime-type match. A freshly built `DateTime` therefore
/// keeps its zone — but a value read back from a row written before that
/// adapter existed comes back as a `DateTimeWithoutTZ`, whose runtime type
/// matches the zone-losing adapter *exactly*, so re-writing it strands it
/// in that lane permanently. An int has no zone to lose, needs no adapter,
/// and is the same shape `milo.db` already stores its timestamps in.
abstract class SyncStamped {
  /// The box key this record is stored under.
  String get id;

  /// When this record last changed locally, in epoch milliseconds (UTC).
  ///
  /// Null only on a record written before the sync migration ran, which
  /// `HiveMigrations` backfills at startup.
  int? get updatedAtMillis;

  /// Soft delete. Filtered out of every read path; kept in the box so the
  /// deletion itself can be pushed to the other device.
  bool get isDeleted;

  /// The [updatedAtMillis] value at the moment this record was last pushed
  /// or pulled successfully. Null means it has never been synced.
  int? get syncedAtMillis;
}

extension SyncStampedX on SyncStamped {
  /// Whether this record holds a local change the server has not seen.
  ///
  /// Compares the device clock against itself, never against the server's,
  /// so clock skew between the two devices cannot make a clean record look
  /// dirty or the reverse.
  bool get isDirty => updatedAtMillis != syncedAtMillis;
}
