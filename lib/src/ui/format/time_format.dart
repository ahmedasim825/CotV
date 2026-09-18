/// Time and duration formatting shared across the schedule, task and
/// lockout UIs, so every surface renders the same instant identically.
library;

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Zero-pads a clock component to two digits: `padTwo(5)` is `05`.
///
/// Public because the time wheel labels its columns one number at a time and
/// has no [DateTime] to hand to [formatClock]. Everything that renders a time
/// in this app pads it, and this is the one place that decides how.
String padTwo(int value) => value.toString().padLeft(2, '0');

/// The name of a month, 1-based: `monthName(9)` is `September`.
///
/// [formatFullDate] and [formatShortDate] both bake a weekday and a day number
/// around the name; this is for the surfaces that want the month on its own.
String monthName(int month) => _monthNames[month - 1];

/// 24-hour clock time, e.g. `05:42`. Matches the prayer cards from Part 1.
String formatClock(DateTime time) => '${padTwo(time.hour)}:${padTwo(time.minute)}';

/// An hour label for the timeline gutter, e.g. `05` for 05:00.
String formatHourLabel(int hour) => padTwo(hour);

/// A time span, e.g. `12:15 – 12:45`.
String formatTimeRange(DateTime start, DateTime end) =>
    '${formatClock(start)} – ${formatClock(end)}';

/// `Tuesday, 1 September` — the schedule header's date line.
String formatFullDate(DateTime date) =>
    '${_weekdayNames[date.weekday - 1]}, ${date.day} ${_monthNames[date.month - 1]}';

/// `Tue 1 Sep` — the compact form for narrow headers.
String formatShortDate(DateTime date) =>
    '${_weekdayNames[date.weekday - 1].substring(0, 3)} ${date.day} '
    '${_monthNames[date.month - 1].substring(0, 3)}';

/// Midnight on the day [date] falls in.
///
/// The app's one date normaliser. Every comparison that means "the same day"
/// rather than "the same instant" runs both sides through this first — prayer
/// windows, the tasks screen's day grouping, [relativeDayName] below. It lives
/// here rather than in `prayer_providers.dart`, where it started, because it
/// is a date fact and not a prayer one, and the tasks screen has no business
/// importing the prayer providers to get at it.
DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

/// Monday-start week bucket for [date].
DateTime weekStartOf(DateTime date) {
  final day = startOfDay(date);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// How many days [date]'s month has.
///
/// Day zero of the following month is the last day of this one, which is how
/// you get 28 / 29 / 30 / 31 out of [DateTime]'s own normalisation rather than
/// out of a table with a leap-year rule in it.
int daysInMonth(DateTime date) => DateTime(date.year, date.month + 1, 0).day;

/// "Today" / "Tomorrow" / "Yesterday" where they apply, otherwise null.
/// Both arguments should be midnight-normalized.
String? relativeDayName(DateTime date, DateTime today) {
  final difference = date.difference(today).inDays;
  switch (difference) {
    case 0:
      return 'Today';
    case 1:
      return 'Tomorrow';
    case -1:
      return 'Yesterday';
    default:
      return null;
  }
}

/// A countdown in its largest two units, e.g. `1h 20m`, `14m 05s`, `48s`.
///
/// Seconds appear only under a minute, and again as the second unit under an
/// hour, so a long countdown doesn't visibly churn every second while a
/// short one still feels live.
String formatCountdown(Duration remaining) {
  if (remaining <= Duration.zero) return '0s';

  final hours = remaining.inHours;
  final minutes = remaining.inMinutes.remainder(60);
  final seconds = remaining.inSeconds.remainder(60);

  if (hours > 0) return '${hours}h ${padTwo(minutes)}m';
  if (minutes > 0) return '${minutes}m ${padTwo(seconds)}s';
  return '${seconds}s';
}

/// A coarse duration for block subtitles, e.g. `30 min`, `1h 30m`, `2h`.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// How a task's due date reads on its list tile: a bare time for today,
/// otherwise a date, with the time appended when it isn't midnight.
String formatDueLabel(DateTime due, DateTime today) {
  final dueDay = DateTime(due.year, due.month, due.day);
  final relative = relativeDayName(dueDay, DateTime(today.year, today.month, today.day));
  final hasTimeOfDay = due.hour != 0 || due.minute != 0;

  if (relative == 'Today') {
    return hasTimeOfDay ? formatClock(due) : 'Today';
  }
  final day = relative ?? formatShortDate(due);
  return hasTimeOfDay ? '$day · ${formatClock(due)}' : day;
}

/// A reminder's due label, e.g. `Yesterday, 03:00` or `27/07/2026, 20:00`.
///
/// Neither [formatDueLabel] nor [formatShortDate] produce this shape, so it
/// lives here as its own helper rather than being assembled inline in a
/// widget. A reminder always carries a precise time — unlike a task's due
/// date, there is no "no time of day" state to special-case — so the time is
/// never dropped, and a numeric `dd/mm/yyyy` stands in for the weekday-name
/// form once the date is more than a day away in either direction.
/// A reminder's due line on the tasks screen, e.g. `Today at 18:00`,
/// `Yesterday at 03:00`, `27 Jul at 20:00`.
///
/// Separate from [formatReminderDueLabel] rather than replacing it: that one
/// produces the comma-and-numeric-date shape the dashboard cards render and
/// the screen tests assert on, and this one is a full sentence fragment
/// because it sits under a title rather than inside a chip.
///
/// 24-hour throughout, matching [formatClock] and every other time in the
/// app.
String formatReminderDueLine(DateTime due, DateTime today) {
  final relative = relativeDayName(startOfDay(due), startOfDay(today));
  final day = relative ?? formatShortDate(due);
  return '$day at ${formatClock(due)}';
}

String formatReminderDueLabel(DateTime due, DateTime today) {
  final dueDay = DateTime(due.year, due.month, due.day);
  final relative = relativeDayName(dueDay, DateTime(today.year, today.month, today.day));
  final day = relative ?? '${padTwo(due.day)}/${padTwo(due.month)}/${due.year}';
  return '$day, ${formatClock(due)}';
}
