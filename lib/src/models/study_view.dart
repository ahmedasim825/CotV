import 'habit_view.dart' show daysInMonth, normalizeDay, weekStartOf;
import 'study_log.dart';
import 'subject.dart';

/// What a full day of study looks like on a ring.
///
/// A target rather than a measurement, so it is a constant on purpose: the
/// stored user settings carry no study goal to read it from, and a ring needs
/// something to be a fraction of. Both the Study screen and the home
/// breakdown card quote it, which is why it lives here rather than beside
/// either of them.
const int dailyStudyGoalMinutes = 480;

/// Totals for one subject over the two windows the screen shows.
class SubjectStudyTotal {
  const SubjectStudyTotal({
    required this.subjectId,
    required this.subjectName,
    required this.todayMinutes,
    required this.weekMinutes,
    required this.todaySessions,
  });

  final String subjectId;

  /// Taken from the logs rather than the subject list, so a subject deleted
  /// after the fact still names itself in the totals it contributed to.
  final String subjectName;

  final int todayMinutes;

  /// Minutes since the start of the containing Monday-start week, today
  /// included.
  final int weekMinutes;

  final int todaySessions;
}

/// Aggregate figures for the strip above the subject grid.
class StudySummary {
  const StudySummary({
    required this.todayMinutes,
    required this.weekMinutes,
    required this.todaySessions,
    required this.bySubject,
  });

  final int todayMinutes;
  final int weekMinutes;
  final int todaySessions;

  /// Every subject with time against it in the current week, busiest first.
  /// Keyed lookups go through [totalFor]; the list order is what the UI
  /// renders.
  final List<SubjectStudyTotal> bySubject;

  bool get isEmpty => weekMinutes == 0;

  /// Totals for [subjectId], or null if it has no time this week.
  SubjectStudyTotal? totalFor(String subjectId) {
    for (final total in bySubject) {
      if (total.subjectId == subjectId) return total;
    }
    return null;
  }

  /// The daily average across the week so far, in minutes — the week's
  /// total spread over the days that have actually happened, not over
  /// seven, so a Tuesday reading is not diluted by five days that have not
  /// arrived yet.
  int dailyAverageMinutes(DateTime now) {
    final daysElapsed = normalizeDay(now).difference(weekStartOf(now)).inDays + 1;
    return weekMinutes ~/ daysElapsed;
  }
}

/// Today's and this week's study totals, overall and per subject.
///
/// Pure, and tested directly rather than through a widget: this is the
/// transform the summary strip, the subject tiles and Milo's context block
/// all read the same numbers from.
StudySummary summarizeStudy(List<StudyLog> logs, DateTime now) {
  final today = normalizeDay(now);
  final weekStart = weekStartOf(now);

  var todayMinutes = 0;
  var weekMinutes = 0;
  var todaySessions = 0;

  final todayBySubject = <String, int>{};
  final weekBySubject = <String, int>{};
  final sessionsBySubject = <String, int>{};
  final names = <String, String>{};

  for (final log in logs) {
    final day = normalizeDay(log.timestamp);
    if (day.isBefore(weekStart)) continue;

    // A log dated after today belongs to a later week's reading, not this
    // one — a device whose clock moved backwards is the realistic way one
    // gets here.
    if (day.isAfter(today)) continue;

    names[log.subjectId] = log.subjectName;
    weekMinutes += log.durationMinutes;
    weekBySubject[log.subjectId] =
        (weekBySubject[log.subjectId] ?? 0) + log.durationMinutes;

    if (day == today) {
      todayMinutes += log.durationMinutes;
      todaySessions++;
      todayBySubject[log.subjectId] =
          (todayBySubject[log.subjectId] ?? 0) + log.durationMinutes;
      sessionsBySubject[log.subjectId] =
          (sessionsBySubject[log.subjectId] ?? 0) + 1;
    }
  }

  final totals = [
    for (final entry in weekBySubject.entries)
      SubjectStudyTotal(
        subjectId: entry.key,
        subjectName: names[entry.key] ?? entry.key,
        todayMinutes: todayBySubject[entry.key] ?? 0,
        weekMinutes: entry.value,
        todaySessions: sessionsBySubject[entry.key] ?? 0,
      ),
  ]..sort((a, b) {
      final byWeek = b.weekMinutes.compareTo(a.weekMinutes);
      if (byWeek != 0) return byWeek;
      // Alphabetical last so the order is total and never reshuffles
      // between rebuilds.
      return a.subjectName.toLowerCase().compareTo(b.subjectName.toLowerCase());
    });

  return StudySummary(
    todayMinutes: todayMinutes,
    weekMinutes: weekMinutes,
    todaySessions: todaySessions,
    bySubject: List.unmodifiable(totals),
  );
}

/// Minutes logged against each day of one month.
class MonthStudy {
  const MonthStudy({
    required this.year,
    required this.month,
    required this.minutesByDay,
    required this.busiestDayMinutes,
  });

  final int year;
  final int month;

  /// One entry per day of the month, the 1st at index 0. The length is the
  /// month's own day count, so February and March produce different lists —
  /// the grid reads it for how many squares to draw.
  final List<int> minutesByDay;

  /// Minutes on the busiest day, or 0 for a month with nothing logged.
  ///
  /// The grid shades each day against this rather than against a fixed
  /// target, so it is carried here rather than rescanned once per square.
  final int busiestDayMinutes;

  int get days => minutesByDay.length;

  bool get isEmpty => busiestDayMinutes == 0;

  /// Minutes logged on [day] of the month, 1-based.
  int minutesOn(int day) => minutesByDay[day - 1];
}

/// Minutes studied on each day of [now]'s month.
///
/// A second transform rather than a widening of [summarizeStudy]: that one
/// starts at the containing Monday and buckets by subject, and stretching it
/// to a month would change every number the summary strip, the subject tiles
/// and Milo's context block read off it.
MonthStudy summarizeStudyMonth(List<StudyLog> logs, DateTime now) {
  final minutes = List<int>.filled(daysInMonth(now), 0);

  for (final log in logs) {
    final at = log.timestamp;
    // Same month of the same year, so a log from last September cannot land
    // in this one's grid.
    if (at.year != now.year || at.month != now.month) continue;
    minutes[at.day - 1] += log.durationMinutes;
  }

  var busiest = 0;
  for (final value in minutes) {
    if (value > busiest) busiest = value;
  }

  return MonthStudy(
    year: now.year,
    month: now.month,
    minutesByDay: List.unmodifiable(minutes),
    busiestDayMinutes: busiest,
  );
}

/// Orders the grid: what has been studied today first (that is what the
/// screen is for), then by this week's total, then alphabetically so the
/// order is total.
List<Subject> sortSubjects(List<Subject> subjects, StudySummary summary) {
  final ordered = [...subjects];
  ordered.sort((a, b) {
    final aTotal = summary.totalFor(a.id);
    final bTotal = summary.totalFor(b.id);

    final byToday =
        (bTotal?.todayMinutes ?? 0).compareTo(aTotal?.todayMinutes ?? 0);
    if (byToday != 0) return byToday;

    final byWeek = (bTotal?.weekMinutes ?? 0).compareTo(aTotal?.weekMinutes ?? 0);
    if (byWeek != 0) return byWeek;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return List.unmodifiable(ordered);
}

/// Minutes as they read in a sentence or on a tile: `0m`, `45m`, `1h 20m`.
///
/// Overlaps `formatDuration` from an hour up, where both render `1h 35m`
/// and `2h`. It exists for the two places they differ: under an hour it
/// gives `45m` rather than `45 min`, which is what fits a half-width
/// subject tile, and it takes the int the study layer already holds rather
/// than a [Duration] built only to be unwrapped again.
String formatStudyMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
