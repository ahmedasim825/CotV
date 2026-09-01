import 'package:hive_ce/hive_ce.dart';

part 'schedule_item.g.dart';

/// A block on the user's day-planner timeline.
///
/// [isPrayerBlocked] marks items generated from (or that must respect) a
/// prayer window — the schedule UI should refuse to overlap these with
/// other bookable items.
@HiveType(typeId: 4)
class ScheduleItem {
  ScheduleItem({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.isPrayerBlocked = false,
    this.notes = '',
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final DateTime startTime;

  @HiveField(3)
  final DateTime endTime;

  @HiveField(4)
  final bool isPrayerBlocked;

  @HiveField(5)
  final String notes;

  Duration get duration => endTime.difference(startTime);

  ScheduleItem copyWith({
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    bool? isPrayerBlocked,
    String? notes,
  }) {
    return ScheduleItem(
      id: id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isPrayerBlocked: isPrayerBlocked ?? this.isPrayerBlocked,
      notes: notes ?? this.notes,
    );
  }
}
