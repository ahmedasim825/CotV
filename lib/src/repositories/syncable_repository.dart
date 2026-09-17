import '../models/sync_stamped.dart';

/// The sync engine's view of a repository.
///
/// Implemented by the Hive repositories *in addition to* their domain
/// interface, so the domain interfaces stay exactly as they were and the
/// engine depends on none of them. That split is what keeps the existing
/// in-memory test fakes compiling untouched: a fake implements
/// `TaskRepository`, not this.
///
/// Why the metadata lives inside the repositories rather than in a
/// decorator over them: `toggleCompleted` and `toggleCompletedOn` do their
/// writes *inside* the Hive classes, so a decorator would have to either
/// reimplement the streak maths or read-modify-write a second time — a
/// second `box.put`, a second `box.watch()` event, a visible double
/// render. A decorator also cannot express [applyRemote], which is the one
/// write that must *not* stamp.
abstract class SyncableRepository<T extends SyncStamped> {
  /// Every record in the box, tombstones included.
  ///
  /// The push path needs the tombstones — a deletion is a change to send,
  /// not an absence.
  List<T> allIncludingDeleted();

  /// Writes [record] exactly as given, without stamping
  /// [SyncStamped.updatedAtMillis].
  ///
  /// A pulled record must keep the timestamp it arrived with. Stamping it
  /// with the local clock would make it read as locally-modified forever,
  /// and the two devices would push it back and forth indefinitely.
  Future<void> applyRemote(T record);

  /// Records that the server has seen the state of [id] as of [millis].
  ///
  /// A no-op if the record's current [SyncStamped.updatedAtMillis] is no
  /// longer [millis] — the user edited it again between the push starting
  /// and this landing, and marking it clean would strand that edit.
  Future<void> markSynced(String id, int millis);

  /// Hard-deletes tombstones that the server has acknowledged and that are
  /// older than [millis]. Returns how many were removed.
  ///
  /// Only safe to call after a clean full sync while signed in: a device
  /// that drops its tombstones before pushing them resurrects those rows
  /// the next time it pulls.
  Future<int> purgeTombstonesBefore(int millis);
}
