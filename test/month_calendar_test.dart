// The task sheet's day grid, which starts its week on Saturday rather than on
// the Monday `weekStartOf` uses for the study week. September 2026 is the
// design's own example: the 1st is a Tuesday and the 18th a Friday.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/ui/tasks/widgets/month_calendar.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

final _september = DateTime(2026, 9);

Future<List<DateTime>> _pumpCalendar(
  WidgetTester tester, {
  DateTime? month,
  DateTime? selected,
  bool pickingMonth = false,
}) async {
  final taps = <DateTime>[];

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 345,
            child: MonthCalendar(
              month: month ?? _september,
              selected: selected ?? DateTime(2026, 9, 18),
              pickingMonth: pickingMonth,
              onTogglePicking: () {},
              onMonthChanged: (_) {},
              onSelected: taps.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  testWidgets('the week runs Saturday to Friday', (tester) async {
    await _pumpCalendar(tester);

    expect(find.text('SAT'), findsOneWidget);
    expect(find.text('FRI'), findsOneWidget);

    // Column order, read off the rendered x positions rather than asserted
    // against an internal list.
    final headers = ['SAT', 'SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI'];
    var previous = double.negativeInfinity;
    for (final header in headers) {
      final x = tester.getCenter(find.text(header)).dx;
      expect(x, greaterThan(previous), reason: '$header is out of order');
      previous = x;
    }
  });

  testWidgets('the 1st lands under the weekday it actually falls on',
      (tester) async {
    await _pumpCalendar(tester);

    // 1 September 2026 is a Tuesday, so it shares a column with TUE — which
    // is the fourth column only because the week starts on Saturday.
    expect(
      tester.getCenter(find.text('1')).dx,
      moreOrLessEquals(tester.getCenter(find.text('TUE')).dx, epsilon: 0.5),
    );
    // And the 18th is a Friday, the last column.
    expect(
      tester.getCenter(find.text('18')).dx,
      moreOrLessEquals(tester.getCenter(find.text('FRI')).dx, epsilon: 0.5),
    );
  });

  testWidgets('every day of the month is drawn, and no more', (tester) async {
    await _pumpCalendar(tester);

    expect(find.text('30'), findsOneWidget);
    // September has 30 days; a 31 would mean the grid ran past the month.
    expect(find.text('31'), findsNothing);
  });

  testWidgets('February 2028 gets its leap day', (tester) async {
    await _pumpCalendar(
      tester,
      month: DateTime(2028, 2),
      selected: DateTime(2028, 2, 1),
    );

    expect(find.text('29'), findsOneWidget);
    expect(find.text('30'), findsNothing);
  });

  testWidgets('tapping a day reports that date', (tester) async {
    final taps = await _pumpCalendar(tester);

    await tester.tap(find.text('7'));
    await tester.pumpAndSettle();

    expect(taps, [DateTime(2026, 9, 7)]);
  });

  testWidgets('the header names the month, and swaps the grid for a wheel',
      (tester) async {
    await _pumpCalendar(tester);
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);

    await _pumpCalendar(tester, pickingMonth: true);

    // The grid is gone and the month/year columns are up: three-letter months
    // against two-digit years.
    expect(find.text('SAT'), findsNothing);
    expect(find.text('Sep'), findsOneWidget);
    expect(find.text('26'), findsOneWidget);
  });
}
