// Exercises the prayer window derivation, in particular the Isha window
// that runs past midnight into the next day's Fajr — the one window a
// single day's timings cannot express on its own.

import 'package:adhan/adhan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/calendar_sync_models.dart';
import 'package:cotv/src/models/daily_prayer_times.dart';
import 'package:cotv/src/models/prayer_window.dart';

final _date = DateTime(2026, 9, 1);

DateTime _at(int hour, int minute) =>
    DateTime(_date.year, _date.month, _date.day, hour, minute);

final _timings = DailyPrayerTimes(
  date: _date,
  coordinates: Coordinates(30.0444, 31.2357),
  calculationMethod: CalculationMethod.egyptian,
  madhab: Madhab.shafi,
  fajr: _at(4, 30),
  sunrise: _at(6, 0),
  dhuhr: _at(12, 0),
  asr: _at(15, 30),
  maghrib: _at(18, 15),
  isha: _at(19, 45),
);

/// Next day's Fajr, which closes the Isha window.
final _nextDayFajr = DateTime(2026, 9, 2, 4, 31);

DailyPrayerSchedule _schedule({Duration lockout = const Duration(minutes: 30)}) {
  return DailyPrayerSchedule.from(
    timings: _timings,
    nextDayFajr: _nextDayFajr,
    lockoutWindows: [
      PrayerLockoutWindow(
        prayer: PrayerLabel.fajr,
        start: _timings.fajr,
        end: _timings.sunrise,
      ),
      for (final prayer in const [
        PrayerLabel.dhuhr,
        PrayerLabel.asr,
        PrayerLabel.maghrib,
        PrayerLabel.isha,
      ])
        PrayerLockoutWindow(
          prayer: prayer,
          start: _timings.timeFor(prayer),
          end: _timings.timeFor(prayer).add(lockout),
        ),
    ],
  );
}

void main() {
  group('validity windows', () {
    test('Fajr runs to Sunrise, not to Dhuhr', () {
      final fajr = _schedule().timeWindows.first;
      expect(fajr.prayer, PrayerLabel.fajr);
      expect(fajr.end, _timings.sunrise);
    });

    test('Isha runs past midnight to the next day\'s Fajr', () {
      final isha = _schedule().timeWindows.last;
      expect(isha.prayer, PrayerLabel.isha);
      expect(isha.end, _nextDayFajr);
      expect(isha.duration, greaterThan(const Duration(hours: 8)));
    });

    test('the Sunrise-to-Dhuhr gap belongs to no prayer', () {
      expect(_schedule().timeWindowAt(_at(9, 0)), isNull);
    });

    test('a window contains its start but not its end', () {
      final schedule = _schedule();
      expect(schedule.timeWindowAt(_timings.dhuhr)?.prayer, PrayerLabel.dhuhr);
      // Asr's start is Dhuhr's end.
      expect(schedule.timeWindowAt(_timings.asr)?.prayer, PrayerLabel.asr);
    });

    test('windows do not overlap', () {
      final windows = _schedule().timeWindows;
      for (var i = 0; i < windows.length - 1; i++) {
        expect(
          windows[i].end.isAfter(windows[i + 1].start),
          isFalse,
          reason: '${windows[i].prayer} overlaps ${windows[i + 1].prayer}',
        );
      }
    });

    test('remaining time is floored at zero once the window has closed', () {
      final dhuhr = _schedule().timeWindows[1];
      expect(dhuhr.remainingAt(_at(23, 0)), Duration.zero);
    });

    test('progress is clamped to 0..1', () {
      final dhuhr = _schedule().timeWindows[1];
      expect(dhuhr.progressAt(_at(4, 0)), 0.0);
      expect(dhuhr.progressAt(_at(23, 0)), 1.0);
      expect(dhuhr.progressAt(_at(13, 45)), closeTo(0.5, 0.01));
    });
  });

  group('lockout windows', () {
    test('a time inside a lockout resolves to it', () {
      expect(_schedule().lockoutAt(_at(12, 15))?.prayer, PrayerLabel.dhuhr);
    });

    test('a time between lockouts resolves to none', () {
      // Dhuhr's lockout has closed by 12:45; Asr's has not opened.
      expect(_schedule().lockoutAt(_at(14, 0)), isNull);
    });

    test('lockouts are shorter than validity windows for non-Fajr prayers', () {
      final schedule = _schedule();
      final dhuhrLockout = schedule.lockoutWindows[1];
      final dhuhrWindow = schedule.timeWindows[1];

      expect(dhuhrLockout.prayer, PrayerLabel.dhuhr);
      expect(
        dhuhrLockout.end.difference(dhuhrLockout.start),
        lessThan(dhuhrWindow.duration),
      );
    });
  });

  group('nextAdhanAfter', () {
    test('returns the next obligatory prayer', () {
      final next = _schedule().nextAdhanAfter(_at(13, 0));
      expect(next?.prayer, PrayerLabel.asr);
      expect(next?.time, _timings.asr);
    });

    test('skips Sunrise, which has no Adhan', () {
      final next = _schedule().nextAdhanAfter(_at(5, 0));
      expect(next?.prayer, PrayerLabel.dhuhr);
    });

    test('returns null after Isha so the caller rolls to tomorrow', () {
      expect(_schedule().nextAdhanAfter(_at(21, 0)), isNull);
    });
  });
}
