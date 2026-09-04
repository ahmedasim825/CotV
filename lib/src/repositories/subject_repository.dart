import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/subject.dart';
import 'hive_repository_utils.dart';

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

class HiveSubjectRepository implements SubjectRepository {
  HiveSubjectRepository(this._box);

  final Box<Subject> _box;

  @override
  Stream<List<Subject>> watchAll() => watchBoxValues(_box);

  @override
  List<Subject> getAll() => _box.values.toList(growable: false);

  @override
  Subject? findByName(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final subject in _box.values) {
      if (subject.name.trim().toLowerCase() == needle) return subject;
    }
    return null;
  }

  @override
  Future<void> add(Subject subject) => _box.put(subject.id, subject);

  @override
  Future<void> update(Subject subject) => _box.put(subject.id, subject);

  @override
  Future<void> delete(String id) => _box.delete(id);
}
