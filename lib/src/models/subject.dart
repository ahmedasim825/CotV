import 'package:hive_ce/hive_ce.dart';

import 'sync_stamped.dart';

part 'subject.g.dart';

/// A thing being studied — Physiology, Anatomy, Pharmacology.
///
/// Sessions are logged against a subject rather than free text so that
/// "how long on Anatomy this week" is a lookup instead of a string match,
/// and so Milo can answer it without guessing what counts as the same
/// subject.
@HiveType(typeId: 8)
class Subject implements SyncStamped {
  Subject({
    required this.id,
    required this.name,
    required this.colorValue,
    DateTime? createdAt,
    this.updatedAtMillis,
    this.isDeleted = false,
    this.syncedAtMillis,
  }) : createdAt = createdAt ?? DateTime.now();

  @HiveField(0)
  @override
  final String id;

  @HiveField(1)
  final String name;

  /// The subject's colour as a 32-bit ARGB value.
  ///
  /// Stored as an int rather than a `Color` so this model carries no
  /// Flutter import and can be read by anything, including the summariser
  /// that has no UI.
  @HiveField(2)
  final int colorValue;

  @HiveField(3)
  final DateTime createdAt;

  /// See [SyncStamped].
  @HiveField(4)
  @override
  final int? updatedAtMillis;

  @HiveField(5)
  @override
  final bool isDeleted;

  @HiveField(6)
  @override
  final int? syncedAtMillis;

  Subject copyWith({String? name, int? colorValue}) => Subject(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        createdAt: createdAt,
        // Carried forward, not exposed — see the note on Task.copyWith.
        updatedAtMillis: updatedAtMillis,
        isDeleted: isDeleted,
        syncedAtMillis: syncedAtMillis,
      );

  /// This subject marked as changed at [millis]. Called by the repository
  /// on the way to the box, never by UI code.
  Subject stampUpdated(int millis) => _sync(updatedAtMillis: millis);

  /// A tombstone: still in the box so the deletion can be pushed, filtered
  /// out of every read path — [SubjectRepository.findByName] included,
  /// since that is Milo's tool-dispatch path.
  Subject markDeleted(int millis) =>
      _sync(updatedAtMillis: millis, isDeleted: true);

  /// Records that the server has seen this record's current state.
  Subject markSynced(int millis) => _sync(syncedAtMillis: millis);

  Subject _sync({int? updatedAtMillis, bool? isDeleted, int? syncedAtMillis}) =>
      Subject(
        id: id,
        name: name,
        colorValue: colorValue,
        createdAt: createdAt,
        updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
        isDeleted: isDeleted ?? this.isDeleted,
        syncedAtMillis: syncedAtMillis ?? this.syncedAtMillis,
      );

  @override
  String toString() => 'Subject($id, $name)';
}
