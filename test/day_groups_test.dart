// Exercises the tasks screen's day grouping. The rule that matters most:
// anything dated after today is dropped rather than bucketed, so this is also
// the test that pins how a future-dated task disappears from that screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/day_groups.dart';

final _now = DateTime(2026, 9, 17, 12, 0);

/// A dated item, standing in for a task or a reminder. `groupByDay` is
/// generic over the row type and only ever reads the date `dateOf` hands
/// back, so the tests use the smallest thing that can carry one.
class _Item {
  const _Item(this.id, this.date);
  final String id;
  final DateTime date;
}

List<DaySection<_Item>> _group(List<_Item> items) =>
    groupByDay(items, dateOf: (item) => item.date, now: _now);

Map<String, List<String>> _shape(List<DaySection<_Item>> sections) => {
      for (final section in sections)
        section.title: section.items.map((i) => i.id).toList(),
    };

void main() {
  group('bucket boundaries', () {
    test('today lands under Today', () {
      final sections = _group([_Item('a', DateTime(2026, 9, 17, 23, 59))]);
      expect(_shape(sections), {'Today': ['a']});
    });

    test('a time earlier today still lands under Today', () {
      final sections = _group([_Item('a', DateTime(2026, 9, 17, 0, 1))]);
      expect(_shape(sections), {'Today': ['a']});
    });

    test('yesterday gets its own section', () {
      final sections = _group([_Item('a', DateTime(2026, 9, 16, 8, 0))]);
      expect(_shape(sections), {'Today': <String>[], 'Yesterday': ['a']});
    });

    test('two days back falls into Last 7 days, not Yesterday', () {
      final sections = _group([_Item('a', DateTime(2026, 9, 15, 8, 0))]);
      expect(_shape(sections), {'Today': <String>[], 'Last 7 days': ['a']});
    });

    test('seven days back is the last day still included', () {
      final sections = _group([_Item('a', DateTime(2026, 9, 10, 0, 0))]);
      expect(_shape(sections), {'Today': <String>[], 'Last 7 days': ['a']});
    });

    test('eight days back is dropped', () {
      final sections = _group([_Item('a', DateTime(2026, 9, 9, 23, 59))]);
      expect(_shape(sections), {'Today': <String>[]});
    });
  });

  group('future dates', () {
    test('tomorrow is dropped, not bucketed', () {
      final sections = _group([_Item('a', DateTime(2026, 9, 18, 0, 0))]);
      expect(_shape(sections), {'Today': <String>[]});
    });

    test('a date far ahead is dropped', () {
      final sections = _group([_Item('a', DateTime(2027, 1, 1))]);
      expect(_shape(sections), {'Today': <String>[]});
    });
  });

  group('sections', () {
    test('Today is returned even when it is empty', () {
      final sections = _group([]);
      expect(_shape(sections), {'Today': <String>[]});
    });

    test('empty past sections are omitted', () {
      final sections = _group([_Item('a', DateTime(2026, 9, 15))]);
      expect(sections.map((s) => s.title), ['Today', 'Last 7 days']);
    });

    test('sections come back newest first', () {
      final sections = _group([
        _Item('old', DateTime(2026, 9, 12)),
        _Item('now', DateTime(2026, 9, 17)),
        _Item('prev', DateTime(2026, 9, 16)),
      ]);
      expect(sections.map((s) => s.title), ['Today', 'Yesterday', 'Last 7 days']);
    });

    test('items keep their incoming order within a section', () {
      final sections = _group([
        _Item('b', DateTime(2026, 9, 17, 9, 0)),
        _Item('a', DateTime(2026, 9, 17, 8, 0)),
      ]);
      expect(_shape(sections), {'Today': ['b', 'a']});
    });

    test('only Today is live; the rest report themselves as past', () {
      final sections = _group([
        _Item('a', DateTime(2026, 9, 16)),
        _Item('b', DateTime(2026, 9, 14)),
      ]);
      expect(sections.map((s) => s.isPast), [false, true, true]);
    });
  });

  test('a day offset is not thrown off by a daylight-saving boundary', () {
    // Europe/London springs forward on 29 March 2026, so the local midnights
    // either side of it are 23 hours apart. Grouped by a raw
    // `difference(...).inDays`, the 29th would read as 0 days from the 30th
    // and file yesterday's rows under Today.
    final sections = groupByDay(
      [_Item('a', DateTime(2026, 3, 29, 12, 0))],
      dateOf: (item) => item.date,
      now: DateTime(2026, 3, 30, 12, 0),
    );
    expect(_shape(sections), {'Today': <String>[], 'Yesterday': ['a']});
  });
}
