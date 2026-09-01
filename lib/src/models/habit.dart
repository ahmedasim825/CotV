import 'package:hive_ce/hive_ce.dart';

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
class Habit {
  Habit({
    required this.id,
    required this.title,
    this.frequency = HabitFrequency.daily,
    List<DateTime>? completedDates,
    this.streakCount = 0,
    this.colorHex = '#D8A657',
  }) : completedDates = completedDates ?? const [];

  @HiveField(0)
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
    );
  }
}
