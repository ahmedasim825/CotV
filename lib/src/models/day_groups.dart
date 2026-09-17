import '../ui/format/time_format.dart';

/// Which day-section an item falls into on the tasks screen.
enum DayBucket { today, yesterday, lastSevenDays }

extension DayBucketX on DayBucket {
  /// The section heading.
  String get title {
    switch (this) {
      case DayBucket.today:
        return 'Today';
      case DayBucket.yesterday:
        return 'Yesterday';
      case DayBucket.lastSevenDays:
        return 'Last 7 days';
    }
  }

  /// Everything but [DayBucket.today] is rendered dimmed, and is not where a
  /// new item gets added.
  bool get isPast => this != DayBucket.today;
}

/// One heading plus the items under it.
class DaySection<T> {
  const DaySection({required this.bucket, required this.items});

  final DayBucket bucket;
  final List<T> items;

  String get title => bucket.title;
  bool get isPast => bucket.isPast;
}

/// Splits [items] into Today / Yesterday / Last 7 days by the date [dateOf]
/// reports, newest section first.
///
/// Anything dated later than today is **dropped**, not bucketed: the screen
/// this feeds shows the recent past and today, and has no section a future
/// item could appear in. That is a deliberate consequence of the design and
/// the one thing to remember about this function — a task due tomorrow is
/// invisible here, though the form sheet reached from the dashboard can still
/// create one. Anything older than seven days is dropped for the same reason.
///
/// Empty sections are omitted, except [DayBucket.today], which is always
/// returned: it carries the inline add row, so the screen would lose its only
/// way to add an item on a day that starts empty.
///
/// The bounds are inclusive of the seventh day back, so "Last 7 days" spans
/// the six days between yesterday and a week ago — yesterday has a heading of
/// its own and is not counted twice.
List<DaySection<T>> groupByDay<T>(
  Iterable<T> items, {
  required DateTime Function(T) dateOf,
  required DateTime now,
}) {
  final today = startOfDay(now);
  final buckets = <DayBucket, List<T>>{
    for (final bucket in DayBucket.values) bucket: <T>[],
  };

  for (final item in items) {
    final offset = _dayOffset(dateOf(item), today);
    final bucket = switch (offset) {
      0 => DayBucket.today,
      -1 => DayBucket.yesterday,
      <= -2 && >= -7 => DayBucket.lastSevenDays,
      _ => null,
    };
    if (bucket != null) buckets[bucket]!.add(item);
  }

  return [
    for (final bucket in DayBucket.values)
      if (bucket == DayBucket.today || buckets[bucket]!.isNotEmpty)
        DaySection(bucket: bucket, items: List.unmodifiable(buckets[bucket]!)),
  ];
}

/// Whole days from [today] to the day [date] falls in: 0 today, -1 yesterday.
///
/// Both sides are re-read as UTC before subtracting. The obvious
/// `a.difference(b).inDays` is wrong twice a year: across a spring-forward
/// boundary two local midnights are 23 hours apart, which truncates to 0 and
/// would file yesterday's rows under Today. UTC has no such boundary, and
/// only the y/m/d fields are carried over, so this is pure calendar
/// arithmetic with no timezone left in it.
int _dayOffset(DateTime date, DateTime today) {
  final from = DateTime.utc(today.year, today.month, today.day);
  final to = DateTime.utc(date.year, date.month, date.day);
  return to.difference(from).inDays;
}
