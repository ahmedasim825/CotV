import 'package:flutter/material.dart';

import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import 'picker_wheel.dart';

/// The day grid under the task sheet's Date row, and the month/year wheel the
/// header swaps it for.
///
/// Takes the month it shows rather than watching a clock for one, so a test can
/// paint September 2026 without a provider scope — the same reason
/// `StudyMonthGridView` is split from `StudyMonthGrid`.
///
/// ## The week starts on Saturday
///
/// Not an oversight, and not the same as the rest of the app: [weekStartOf] in
/// `time_format.dart` buckets the study week from Monday, and it should keep
/// doing that — a study streak and a calendar answer different questions. This
/// grid follows the design, whose header reads SAT SUN MON TUE WED THU FRI.
///
/// `DateTime.saturday` is 6, so `(weekday + 1) % 7` puts Saturday in column 0
/// and Friday in column 6 without a lookup table.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.onSelected,
    required this.onMonthChanged,
    required this.pickingMonth,
    required this.onTogglePicking,
  });

  /// Any day in the month on show; only its year and month are read.
  final DateTime month;

  /// The chosen day, which need not fall inside [month].
  final DateTime selected;

  final ValueChanged<DateTime> onSelected;

  /// A new month to show, from the steppers or the wheel.
  final ValueChanged<DateTime> onMonthChanged;

  /// Whether the header's month/year wheel has replaced the day grid.
  final bool pickingMonth;

  final VoidCallback onTogglePicking;

  /// The column headings, Saturday first. A local constant rather than
  /// something lifted into `time_format.dart`: the names there are private,
  /// Monday-indexed and title-cased, and a fixed header row is not a formatted
  /// date.
  static const List<String> _columns = [
    'SAT',
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
  ];

  static const double _rowHeight = 32;
  static const double _circle = 28;

  /// The span the year wheel offers. Two back so the current year sits with a
  /// year above it at rest, which is how the design draws it, and eight on for
  /// anything scheduled far out.
  static const int _yearsBack = 2;
  static const int _yearsForward = 8;

  static int _columnOf(DateTime date) => (date.weekday + 1) % 7;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context),
        if (pickingMonth) _wheel(context) else _grid(context),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: pickingMonth ? 'Close month picker' : 'Choose month',
            child: GestureDetector(
              onTap: onTogglePicking,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${monthName(month.month)} ${month.year}',
                    style: context.typography.ui(
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    pickingMonth ? PhLight.caretDown : PhLight.caretRight,
                    size: 14,
                    color: palette.textPrimary,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _stepper(
            context,
            icon: PhLight.caretLeft,
            label: 'Previous month',
            to: DateTime(month.year, month.month - 1),
          ),
          const SizedBox(width: 10),
          _stepper(
            context,
            icon: PhLight.caretRight,
            label: 'Next month',
            to: DateTime(month.year, month.month + 1),
          ),
        ],
      ),
    );
  }

  Widget _stepper(
    BuildContext context, {
    required IconData icon,
    required String label,
    required DateTime to,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () => onMonthChanged(to),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 15, color: context.palette.textPrimary),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final palette = context.palette;
    final first = DateTime(month.year, month.month);
    final blanks = _columnOf(first);
    final days = daysInMonth(first);

    // Blanks then days, padded out so the last row is full and its cells keep
    // the same width as every other row's.
    final cells = <Widget>[
      for (var i = 0; i < blanks; i++) const _Blank(),
      for (var day = 1; day <= days; day++)
        _Day(
          day: day,
          isSelected: _sameDay(
            DateTime(month.year, month.month, day),
            selected,
          ),
          onTap: () => onSelected(DateTime(month.year, month.month, day)),
        ),
    ];
    while (cells.length % _columns.length != 0) {
      cells.add(const _Blank());
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final column in _columns)
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: Center(
                    child: Text(
                      column,
                      style: context.typography.ui(
                        size: 11,
                        weight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var row = 0; row < cells.length; row += _columns.length)
          Row(children: cells.sublist(row, row + _columns.length)),
      ],
    );
  }

  Widget _wheel(BuildContext context) {
    final firstYear = month.year - _yearsBack;
    final yearCount = _yearsBack + _yearsForward + 1;

    return PickerWheel(
      columns: [
        WheelColumn(
          count: 12,
          selected: month.month - 1,
          label: (index) => monthName(index + 1).substring(0, 3),
          onChanged: (index) => onMonthChanged(DateTime(month.year, index + 1)),
        ),
        WheelColumn(
          count: yearCount,
          selected: _yearsBack,
          label: (index) => padTwo((firstYear + index) % 100),
          onChanged: (index) =>
              onMonthChanged(DateTime(firstYear + index, month.month)),
        ),
      ],
    );
  }
}

class _Blank extends StatelessWidget {
  const _Blank();

  @override
  Widget build(BuildContext context) =>
      const Expanded(child: SizedBox(height: MonthCalendar._rowHeight));
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  final int day;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        child: GestureDetector(
          onTap: onTap,
          // The whole cell takes the tap, not just the 28pt disc — the disc is
          // the design's mark for the chosen day, not the target.
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: MonthCalendar._rowHeight,
            child: Center(
              child: Container(
                width: MonthCalendar._circle,
                height: MonthCalendar._circle,
                alignment: Alignment.center,
                decoration: isSelected
                    ? BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(
                  '$day',
                  style: context.typography.ui(
                    size: 14,
                    weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
