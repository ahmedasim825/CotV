import '../ui/format/time_format.dart';

/// Which day-section an item falls into on the tasks screen.
///
/// Six buckets across two ranges that never mix — see [DayRange]. The
/// declaration order means nothing; each range names its own order below,
/// because the two disagree about which end of time to start from.
enum DayBucket {
  today,
  yesterday,
  lastSevenDays,
  tomorrow,
  thisWeek,
  later,
}

/// Which half of the calendar a grouping covers.
///
/// The tasks screen's filter picks one or the other and never both, so a
/// single list never interleaves a "Yesterday" heading with a "Tomorrow" one.
/// That is what lets each range order its sections soonest-first from the
/// user's own position in time rather than agreeing on one global direction.
enum DayRange { pastAndToday, upcoming }

extension DayRangeX on DayRange {
  /// The sections this range emits, in the order they are rendered.
  List<DayBucket> get buckets {
    switch (this) {
      case DayRange.pastAndToday:
        return const [
          DayBucket.today,
          DayBucket.yesterday,
          DayBucket.lastSevenDays,
        ];
      case DayRange.upcoming:
        return const [
          DayBucket.tomorrow,
          DayBucket.thisWeek,
          DayBucket.later,
        ];
    }
  }
}

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
      case DayBucket.tomorrow:
        return 'Tomorrow';
      case DayBucket.thisWeek:
        return 'This week';
      case DayBucket.later:
        return 'Later';
    }
  }

  /// Whether the section renders dimmed.
  ///
  /// Only the two behind us. Today is where you are and the future is not
  /// over, so neither recedes — which is why this is an explicit pair rather
  /// than "anything that is not today", as it was when today was the newest
  /// thing this could return.
  bool get isPast =>
      this == DayBucket.yesterday || this == DayBucket.lastSevenDays;
}

/// One heading plus the items under it.
class DaySection<T> {
  const DaySection({required this.bucket, required this.items});

  final DayBucket bucket;
  final List<T> items;

  String get title => bucket.title;
  bool get isPast => bucket.isPast;
}

/// Splits [items] into day sections by the date [dateOf] reports.
///
/// [range] decides which half of the calendar is on offer, and anything
/// outside it is **dropped, not clamped**: under [DayRange.pastAndToday] a task
/// due tomorrow is invisible, and under [DayRange.upcoming] one due yesterday
/// is. Nothing is ever shown in a section that misdescribes when it is due.
/// Beyond seven days in either direction is dropped as well — "Later" is the
/// one exception, because a list of things you have not reached yet has no
/// natural far edge, while a list of things behind you does.
///
/// Empty sections are omitted, except [DayBucket.today], which
/// [DayRange.pastAndToday] always returns: it carries the inline add row, so
/// the screen would otherwise lose its only way to add an item on a day that
/// starts empty. [DayRange.upcoming] has no such section and so can come back
/// entirely empty.
///
/// The seven-day bounds are inclusive, so "Last 7 days" spans the six days
/// between yesterday and a week ago — yesterday has a heading of its own and is
/// not counted twice. "This week" mirrors it forward.
List<DaySection<T>> groupByDay<T>(
  Iterable<T> items, {
  required DateTime Function(T) dateOf,
  required DateTime now,
  DayRange range = DayRange.pastAndToday,
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
      1 => DayBucket.tomorrow,
      >= 2 && <= 7 => DayBucket.thisWeek,
      _ => offset > 7 ? DayBucket.later : null,
    };
    // Dropped when the bucket belongs to the other half of the calendar, so
    // the range filter and the bucketing cannot disagree.
    if (bucket != null && range.buckets.contains(bucket)) {
      buckets[bucket]!.add(item);
    }
  }

  return [
    for (final bucket in range.buckets)
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
