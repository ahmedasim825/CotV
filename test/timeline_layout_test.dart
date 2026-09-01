// Exercises the timeline's overlap column packing, which decides whether
// two blocks sit side by side or on top of each other. Getting the cluster
// boundaries wrong is invisible in a unit-less UI review but produces
// overlapping, unreadable blocks on a busy day.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/schedule_item.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/timeline_entry.dart';

final _day = DateTime(2026, 9, 1);

DateTime _at(int hour, [int minute = 0]) =>
    DateTime(_day.year, _day.month, _day.day, hour, minute);

TimelineEntry _block(String id, int startHour, int endHour) {
  return ScheduleItemEntry(
    ScheduleItem(
      id: id,
      title: id,
      startTime: _at(startHour),
      endTime: _at(endHour),
    ),
  );
}

PlacedTimelineEntry _find(List<PlacedTimelineEntry> placed, String id) =>
    placed.firstWhere((p) => p.entry.title == id);

void main() {
  test('an empty timeline places nothing', () {
    expect(layoutTimelineEntries(const []), isEmpty);
  });

  test('sequential blocks all share a single column', () {
    final placed = layoutTimelineEntries([
      _block('a', 9, 10),
      _block('b', 10, 11),
      _block('c', 11, 12),
    ]);

    expect(placed, hasLength(3));
    for (final entry in placed) {
      expect(entry.column, 0);
      expect(entry.columnCount, 1);
    }
  });

  test('touching blocks do not count as overlapping', () {
    // a ends exactly when b starts: the ranges are half-open, so they can
    // share a column.
    final placed = layoutTimelineEntries([_block('a', 9, 10), _block('b', 10, 11)]);
    expect(_find(placed, 'b').column, 0);
    expect(_find(placed, 'b').columnCount, 1);
  });

  test('two overlapping blocks split into two columns', () {
    final placed = layoutTimelineEntries([
      _block('a', 9, 11),
      _block('b', 10, 12),
    ]);

    expect(_find(placed, 'a').column, 0);
    expect(_find(placed, 'b').column, 1);
    // Both are widened to the same count so the cluster reads as a grid.
    expect(_find(placed, 'a').columnCount, 2);
    expect(_find(placed, 'b').columnCount, 2);
  });

  test('a freed column is reused within the same cluster', () {
    // a: 9-11, b: 10-12 (forces col 1), c: 11-13 overlaps b but not a, so
    // it may reclaim column 0 rather than opening a third.
    final placed = layoutTimelineEntries([
      _block('a', 9, 11),
      _block('b', 10, 12),
      _block('c', 11, 13),
    ]);

    expect(_find(placed, 'c').column, 0);
    expect(_find(placed, 'c').columnCount, 2);
  });

  test('a gap starts a new cluster with its own column count', () {
    final placed = layoutTimelineEntries([
      _block('a', 9, 11),
      _block('b', 10, 12),
      // Well clear of the first pair.
      _block('c', 15, 16),
    ]);

    expect(_find(placed, 'a').columnCount, 2);
    expect(_find(placed, 'c').column, 0);
    expect(_find(placed, 'c').columnCount, 1);
  });

  test('three mutually overlapping blocks need three columns', () {
    final placed = layoutTimelineEntries([
      _block('a', 9, 12),
      _block('b', 10, 12),
      _block('c', 11, 12),
    ]);

    expect(
      placed.map((p) => p.column).toList()..sort(),
      [0, 1, 2],
    );
    for (final entry in placed) {
      expect(entry.columnCount, 3);
    }
  });

  test('input order does not change the placement', () {
    final forward = layoutTimelineEntries([
      _block('a', 9, 11),
      _block('b', 10, 12),
    ]);
    final reversed = layoutTimelineEntries([
      _block('b', 10, 12),
      _block('a', 9, 11),
    ]);

    expect(_find(reversed, 'a').column, _find(forward, 'a').column);
    expect(_find(reversed, 'b').column, _find(forward, 'b').column);
  });

  test('a task block occupies its synthesised duration', () {
    final due = _at(14, 30);
    final entry = TaskEntry(
      Task(id: 't1', title: 'Write notes', dueDate: due),
      due,
    );

    expect(entry.start, due);
    expect(entry.end, due.add(TaskEntry.taskBlockDuration));
    expect(entry.isReadOnly, isFalse);
  });

  test('prayer lockout entries are read-only', () {
    final entry = _block('a', 9, 10);
    expect(entry.isReadOnly, isFalse);

    final blocked = ScheduleItemEntry(
      ScheduleItem(
        id: 'p',
        title: 'p',
        startTime: _at(9),
        endTime: _at(10),
        isPrayerBlocked: true,
      ),
    );
    expect(blocked.isReadOnly, isTrue);
  });
}
