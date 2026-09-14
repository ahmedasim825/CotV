// Pure-Dart tests for the study aggregation — the transform the summary
// strip, the subject tiles and Milo's context block all read their numbers
// from. No Hive, no widgets.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/habit_view.dart' show daysInMonth;
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/study_view.dart';
import 'package:cotv/src/models/subject.dart';

/// Wednesday, so there are three days of the week behind it and four ahead
/// — enough that "this week" and "seven days" cannot be confused.
final _now = DateTime(2026, 9, 2, 14, 30);

StudyLog _log({
  String id = 'l1',
  String subjectId = 's1',
  String subjectName = 'Physiology',
  int minutes = 45,
  DateTime? at,
}) {
  return StudyLog(
    id: id,
    subjectId: subjectId,
    subjectName: subjectName,
    durationMinutes: minutes,
    timestamp: at ?? _now,
  );
}

void main() {
  group('summarizeStudy', () {
    test('is empty when nothing has been logged', () {
      final summary = summarizeStudy(const [], _now);

      expect(summary.isEmpty, isTrue);
      expect(summary.todayMinutes, 0);
      expect(summary.weekMinutes, 0);
      expect(summary.bySubject, isEmpty);
    });

    test('totals today separately from the week', () {
      final summary = summarizeStudy([
        _log(id: 'a', minutes: 45),
        _log(id: 'b', minutes: 30, at: _now.subtract(const Duration(days: 1))),
        _log(id: 'c', minutes: 20, at: _now.subtract(const Duration(days: 2))),
      ], _now);

      expect(summary.todayMinutes, 45);
      expect(summary.weekMinutes, 95);
      expect(summary.todaySessions, 1);
    });

    test('drops anything before the containing Monday', () {
      // Monday is 2026-08-31, so four days back is the previous week.
      final summary = summarizeStudy([
        _log(id: 'a', minutes: 45),
        _log(id: 'b', minutes: 60, at: _now.subtract(const Duration(days: 4))),
      ], _now);

      expect(summary.weekMinutes, 45);
      expect(summary.bySubject.single.weekMinutes, 45);
    });

    test('sums several sessions on one subject and counts them', () {
      final summary = summarizeStudy([
        _log(id: 'a', minutes: 25),
        _log(id: 'b', minutes: 25),
        _log(id: 'c', minutes: 45),
      ], _now);

      final total = summary.totalFor('s1')!;
      expect(total.todayMinutes, 95);
      expect(total.todaySessions, 3);
      expect(summary.todaySessions, 3);
    });

    test('orders subjects by the week, then by name', () {
      final summary = summarizeStudy([
        _log(id: 'a', subjectId: 's1', subjectName: 'Anatomy', minutes: 30),
        _log(id: 'b', subjectId: 's2', subjectName: 'Physiology', minutes: 90),
        _log(id: 'c', subjectId: 's3', subjectName: 'Pharmacology', minutes: 30),
      ], _now);

      expect(
        [for (final total in summary.bySubject) total.subjectName],
        ['Physiology', 'Anatomy', 'Pharmacology'],
      );
    });

    test('names a subject from the log, not from the subject list', () {
      // The denormalised name is the point: a deleted subject still says
      // what its logged time was for.
      final summary = summarizeStudy([
        _log(subjectId: 'gone', subjectName: 'Biochemistry'),
      ], _now);

      expect(summary.bySubject.single.subjectName, 'Biochemistry');
    });

    test('ignores a log dated after today', () {
      // A device whose clock moved backwards is the realistic way a
      // future-dated log appears; counting it would inflate today.
      final summary = summarizeStudy([
        _log(id: 'a', minutes: 45),
        _log(id: 'b', minutes: 60, at: _now.add(const Duration(days: 1))),
      ], _now);

      expect(summary.todayMinutes, 45);
      expect(summary.weekMinutes, 45);
    });

    test('averages over the days elapsed, not over seven', () {
      // Wednesday is day 3 of the week, so 90 minutes averages 30.
      final summary = summarizeStudy([
        _log(id: 'a', minutes: 30),
        _log(id: 'b', minutes: 60, at: _now.subtract(const Duration(days: 2))),
      ], _now);

      expect(summary.dailyAverageMinutes(_now), 30);
    });
  });

  group('sortSubjects', () {
    Subject subject(String id, String name) =>
        Subject(id: id, name: name, colorValue: 0xFF7B8FCB);

    test("puts today's work first, then the week, then name", () {
      final summary = summarizeStudy([
        // Anatomy has more this week but nothing today.
        _log(id: 'a', subjectId: 's1', subjectName: 'Anatomy', minutes: 120,
            at: _now.subtract(const Duration(days: 1))),
        _log(id: 'b', subjectId: 's2', subjectName: 'Physiology', minutes: 25),
      ], _now);

      final ordered = sortSubjects([
        subject('s1', 'Anatomy'),
        subject('s2', 'Physiology'),
        subject('s3', 'Zoology'),
        subject('s4', 'Biochemistry'),
      ], summary);

      expect(
        [for (final s in ordered) s.name],
        // Physiology (today) > Anatomy (week) > the two untouched, A-Z.
        ['Physiology', 'Anatomy', 'Biochemistry', 'Zoology'],
      );
    });

    test('leaves an untouched list alphabetical', () {
      final ordered = sortSubjects(
        [subject('s2', 'Zoology'), subject('s1', 'Anatomy')],
        summarizeStudy(const [], _now),
      );

      expect([for (final s in ordered) s.name], ['Anatomy', 'Zoology']);
    });
  });

  group('daysInMonth', () {
    test('counts short, long and leap months', () {
      expect(daysInMonth(DateTime(2026, 9, 12)), 30);
      expect(daysInMonth(DateTime(2026, 10, 1)), 31);
      expect(daysInMonth(DateTime(2027, 2, 14)), 28);
      expect(daysInMonth(DateTime(2028, 2, 14)), 29, reason: 'leap year');
      expect(daysInMonth(DateTime(2026, 12, 31)), 31,
          reason: 'December rolls the year over to find day zero of January');
    });
  });

  group('summarizeStudyMonth', () {
    test('an empty month is all zeroes, not an empty list', () {
      final month = summarizeStudyMonth(const [], _now);

      expect(month.days, 30, reason: 'September 2026');
      expect(month.minutesByDay, everyElement(0));
      expect(month.busiestDayMinutes, 0);
      expect(month.isEmpty, isTrue);
    });

    test('buckets by day with the 1st at index 0', () {
      final month = summarizeStudyMonth([
        _log(id: 'a', minutes: 30, at: DateTime(2026, 9, 1, 9)),
        _log(id: 'b', minutes: 45, at: DateTime(2026, 9, 30, 22)),
      ], _now);

      expect(month.minutesByDay.first, 30);
      expect(month.minutesByDay.last, 45);
      expect(month.minutesOn(1), 30);
      expect(month.minutesOn(30), 45);
      expect(month.minutesOn(2), 0);
    });

    test('sums several sessions on the same day', () {
      final month = summarizeStudyMonth([
        _log(id: 'a', minutes: 25, at: DateTime(2026, 9, 2, 9)),
        _log(id: 'b', minutes: 45, at: DateTime(2026, 9, 2, 15)),
        _log(id: 'c', minutes: 20, at: DateTime(2026, 9, 2, 21)),
      ], _now);

      expect(month.minutesOn(2), 90);
      expect(month.busiestDayMinutes, 90);
    });

    test('ignores the months either side', () {
      final month = summarizeStudyMonth([
        _log(id: 'before', minutes: 60, at: DateTime(2026, 8, 31, 23)),
        _log(id: 'inside', minutes: 30, at: DateTime(2026, 9, 4)),
        _log(id: 'after', minutes: 60, at: DateTime(2026, 10, 1)),
        _log(id: 'last year', minutes: 60, at: DateTime(2025, 9, 4)),
      ], _now);

      expect(month.minutesByDay.reduce((a, b) => a + b), 30,
          reason: 'only the September 2026 log counts');
      expect(month.minutesOn(4), 30);
    });

    test('reports the busiest day, which the grid shades everything against',
        () {
      final month = summarizeStudyMonth([
        _log(id: 'a', minutes: 30, at: DateTime(2026, 9, 1)),
        _log(id: 'b', minutes: 200, at: DateTime(2026, 9, 7)),
        _log(id: 'c', minutes: 120, at: DateTime(2026, 9, 9)),
      ], _now);

      expect(month.busiestDayMinutes, 200);
      expect(month.isEmpty, isFalse);
    });

    test('carries the month it summarised', () {
      final month = summarizeStudyMonth(const [], DateTime(2027, 2, 3));

      expect(month.year, 2027);
      expect(month.month, 2);
      expect(month.days, 28);
    });
  });

  group('formatStudyMinutes', () {
    test('renders minutes, hours and both', () {
      expect(formatStudyMinutes(0), '0m');
      expect(formatStudyMinutes(45), '45m');
      expect(formatStudyMinutes(60), '1h');
      expect(formatStudyMinutes(95), '1h 35m');
      expect(formatStudyMinutes(120), '2h');
    });
  });
}
