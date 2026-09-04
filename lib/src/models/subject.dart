import 'package:hive_ce/hive_ce.dart';

part 'subject.g.dart';

/// A thing being studied — Physiology, Anatomy, Pharmacology.
///
/// Sessions are logged against a subject rather than free text so that
/// "how long on Anatomy this week" is a lookup instead of a string match,
/// and so Milo can answer it without guessing what counts as the same
/// subject.
@HiveType(typeId: 8)
class Subject {
  Subject({
    required this.id,
    required this.name,
    required this.colorValue,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  @HiveField(0)
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

  Subject copyWith({String? name, int? colorValue}) => Subject(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        createdAt: createdAt,
      );

  @override
  String toString() => 'Subject($id, $name)';
}
