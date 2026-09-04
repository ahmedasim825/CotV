// Pure-Dart tests for the study aggregation — the transform the summary
// strip, the subject tiles and Milo's context block all read their numbers
// from. No Hive, no widgets.

import 'package:flutter_test/flutter_test.dart';

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
