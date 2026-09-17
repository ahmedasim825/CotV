import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/subject.dart';
import '../models/sync_stamped.dart';
import 'hive_repository_utils.dart';
import 'syncable_repository.dart';

/// CRUD access to [Subject]s.
abstract class SubjectRepository {
  Stream<List<Subject>> watchAll();

  List<Subject> getAll();

  /// The subject whose name matches [name], ignoring case and surrounding
  /// space, or null if there is none.
  ///
  /// Exists for Milo: "start a timer for physiology" arrives as prose, and
  /// the tool that handles it has to resolve that to a real subject rather
  /// than inventing one.
  Subject? findByName(String name);

  Future<void> add(Subject subject);

  Future<void> update(Subject subject);

  Future<void> delete(String id);
}

class HiveSubjectRepository
    implements SubjectRepository, SyncableRepository<Subject> {
  HiveSubjectRepository(this._box, [this._clock = systemSyncClock]);

  final Box<Subject> _box;
  final SyncClock _clock;

  @override
  Stream<List<Subject>> watchAll() => watchLiveBoxValues(_box);

  @override
  List<Subject> getAll() => liveValues(_box.values);

  @override
  Subject? findByName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final subject in _box.values) {
      // Tombstones are skipped here as everywhere else, and it matters more
      // here than most: this is Milo's tool-dispatch path, so a leak means
      // starting a timer against a subject the user deleted.
      if (subject.isDeleted) continue;
      if (subject.name.trim().toLowerCase() == needle) return subject;
    }
    return null;
  }

  @override
  Future<void> add(Subject subject) =>
      _box.put(subject.id, subject.stampUpdated(_clock()));

  @override
  Future<void> update(Subject subject) =>
      _box.put(subject.id, subject.stampUpdated(_clock()));

  /// Tombstones [id] rather than removing it — see [HiveTaskRepository.delete].
  ///
  /// Still does not cascade to [StudyLog]s: `subjectName` is denormalised
  /// deliberately so history survives the subject it was logged against.
  @override
  Future<void> delete(String id) async {
    final subject = _box.get(id);
    if (subject == null) return;
    await _box.put(id, subject.markDeleted(_clock()));
  }

  @override
  List<Subject> allIncludingDeleted() => _box.values.toList(growable: false);

  @override
  Future<void> applyRemote(Subject record) => _box.put(record.id, record);

  @override
  Future<void> markSynced(String id, int millis) async {
    final subject = _box.get(id);
    if (subject == null || subject.updatedAtMillis != millis) return;
    await _box.put(id, subject.markSynced(millis));
  }

  @override
  Future<int> purgeTombstonesBefore(int millis) async {
    final stale = _box.values
        .where((subject) =>
            subject.isDeleted &&
            !subject.isDirty &&
            (subject.updatedAtMillis ?? 0) < millis)
        .map((subject) => subject.id)
        .toList(growable: false);
    await _box.deleteAll(stale);
    return stale.length;
  }
}
