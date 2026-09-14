import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wall-clock time, re-emitted once a second.
///
/// Every live countdown and the timeline's current-time indicator watch
/// this rather than each running their own [Timer], so the whole UI advances
/// on one tick. It is auto-disposed: when no countdown is on screen the
/// timer stops entirely instead of waking the app once a second forever.
///
/// Widgets that only need minute resolution should watch
/// [currentMinuteProvider] instead — it filters this down so they rebuild
/// 60x less often.
final nowTickerProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );
});

/// The current time truncated to the minute.
///
/// Derived from [nowTickerProvider] but only notifies listeners when the
/// minute actually rolls over, because Riverpod skips propagation when a
/// recomputed value compares equal to the previous one.
final currentMinuteProvider = Provider.autoDispose<DateTime>((ref) {
  final now = ref.watch(nowTickerProvider).value ?? DateTime.now();
  return DateTime(now.year, now.month, now.day, now.hour, now.minute);
});

/// Today's date, at midnight.
///
/// One more turn of the same crank as [currentMinuteProvider]: anything that
/// only changes when the date does — a month grid, a "days elapsed" reading —
/// watches this and rebuilds once at midnight instead of once a minute.
final currentDayProvider = Provider.autoDispose<DateTime>((ref) {
  final now = ref.watch(currentMinuteProvider);
  return DateTime(now.year, now.month, now.day);
});
