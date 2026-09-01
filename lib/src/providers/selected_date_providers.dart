import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clock_providers.dart';
import 'prayer_providers.dart' show startOfDay;

/// The day the schedule view is currently showing, always midnight-
/// normalized so it can be used directly as a `Provider.family` key without
/// spawning a fresh provider per millisecond.
class SelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => startOfDay(DateTime.now());

  void select(DateTime date) => state = startOfDay(date);

  void jumpToToday() => state = startOfDay(DateTime.now());

  void offsetByDays(int days) =>
      state = startOfDay(state.add(Duration(days: days)));

  void nextDay() => offsetByDays(1);

  void previousDay() => offsetByDays(-1);
}

final selectedDateProvider =
    NotifierProvider<SelectedDateNotifier, DateTime>(SelectedDateNotifier.new);

/// Whether the schedule view is currently parked on today, which decides
/// whether the current-time indicator and "Jump to Now" control are shown.
///
/// Derived from [currentMinuteProvider] rather than a bare `DateTime.now()`
/// so that leaving the app open across midnight flips this to false instead
/// of stranding a "now" line on yesterday. That makes it auto-dispose, which
/// is correct — the answer only matters while the schedule is on screen.
final isViewingTodayProvider = Provider.autoDispose<bool>((ref) {
  final selected = ref.watch(selectedDateProvider);
  final today = startOfDay(ref.watch(currentMinuteProvider));
  return selected == today;
});
