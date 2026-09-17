import 'package:hive_ce/hive_ce.dart';

import 'sync_stamped.dart';

part 'habit.g.dart';

/// How often a [Habit] is expected to be completed.
@HiveType(typeId: 3)
enum HabitFrequency {
  @HiveField(0)
  daily,
  @HiveField(1)
  weekly,
}

/// A recurring habit tracked by completion dates and a running streak.
@HiveType(typeId: 2)
class Habit implements SyncStamped {
  Habit({
    required this.id,
    required this.title,
    this.frequency = HabitFrequency.daily,
    List<DateTime>? completedDates,
    this.streakCount = 0,
    this.colorHex = '#D8A657',
    this.updatedAtMillis,
    this.isDeleted = false,
    this.syncedAtMillis,
  }) : completedDates = completedDates ?? const [];

  @HiveField(0)
  @override
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final HabitFrequency frequency;

  /// Midnight-normalized dates this habit was marked complete on.
  @HiveField(3)
  final List<DateTime> completedDates;

  @HiveField(4)
  final int streakCount;

  /// e.g. `'#D8A657'` — used to color this habit's UI without a fixed enum.
  @HiveField(5)
  final String colorHex;

  /// See [SyncStamped]. A habit carried no timestamp at all before these
  /// fields, so `HiveMigrations` backfills existing rows from the migration
  /// instant rather than from anything on the record.
  @HiveField(6)
  @override
  final int? updatedAtMillis;

  @HiveField(7)
  @override
  final bool isDeleted;

  @HiveField(8)
  @override
  final int? syncedAtMillis;

  Habit copyWith({
    String? title,
    HabitFrequency? frequency,
    List<DateTime>? completedDates,
    int? streakCount,
    String? colorHex,
  }) {
    return Habit(
      id: id,
      title: title ?? this.title,
      frequency: frequency ?? this.frequency,
      completedDates: completedDates ?? this.completedDates,
      streakCount: streakCount ?? this.streakCount,
      colorHex: colorHex ?? this.colorHex,
      // Carried forward, not exposed — see the note on Task.copyWith.
      updatedAtMillis: updatedAtMillis,
      isDeleted: isDeleted,
      syncedAtMillis: syncedAtMillis,
    );
  }

  /// This habit marked as changed at [millis]. Called by the repository on
  /// the way to the box, never by UI code.
  Habit stampUpdated(int millis) => _sync(updatedAtMillis: millis);

  /// A tombstone: still in the box so the deletion can be pushed, filtered
  /// out of every read path.
  Habit markDeleted(int millis) =>
      _sync(updatedAtMillis: millis, isDeleted: true);

  /// Records that the server has seen this record's current state.
  Habit markSynced(int millis) => _sync(syncedAtMillis: millis);

  Habit _sync({int? updatedAtMillis, bool? isDeleted, int? syncedAtMillis}) =>
      Habit(
        id: id,
        title: title,
        frequency: frequency,
        completedDates: completedDates,
        streakCount: streakCount,
        colorHex: colorHex,
        updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
        isDeleted: isDeleted ?? this.isDeleted,
        syncedAtMillis: syncedAtMillis ?? this.syncedAtMillis,
      );
}
