import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/daily_prayer_times.dart';
import '../../models/prayer_window.dart';
import '../../models/timeline_entry.dart';
import '../../providers/clock_providers.dart';
import '../../providers/prayer_window_providers.dart';
import '../../providers/selected_date_providers.dart';
import '../../providers/timeline_providers.dart';
import '../format/time_format.dart';
import '../responsive/breakpoints.dart';
import '../tasks/task_form_sheet.dart';
import '../theme/app_theme.dart';
import '../theme/prayer_palette.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/prayer_lockout_banner.dart';
import 'widgets/current_time_indicator.dart';
import 'widgets/date_navigation_header.dart';
import 'widgets/timeline_block.dart';
import 'widgets/timeline_geometry.dart';

/// The vertical 24-hour timeline for the selected day.
///
/// Layered back to front: tinted prayer-validity bands, hour rules, the
/// placed blocks, then the current-time indicator. Everything is positioned
/// from a single [TimelineGeometry], so the layers stay registered with each
/// other at any [WindowSize].
class DailyScheduleView extends ConsumerStatefulWidget {
  const DailyScheduleView({super.key, this.showBanner = true});

  /// Suppressed in the iPad split view, where the banner is hoisted above
  /// both panes instead of being repeated in each.
  final bool showBanner;

  @override
  ConsumerState<DailyScheduleView> createState() => _DailyScheduleViewState();
}

class _DailyScheduleViewState extends ConsumerState<DailyScheduleView> {
  final ScrollController _scrollController = ScrollController();

  /// Set once the first frame has laid out, so the initial scroll to "now"
  /// happens without an animation the user never asked for.
  bool _hasPositionedInitially = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scrolls so the given time sits about a third of the way down the
  /// viewport — far enough from the top edge to show what led up to it.
  void _scrollTo(DateTime time, TimelineGeometry geometry, {bool animate = true}) {
    if (!_scrollController.hasClients) return;

    final target = (geometry.offsetOf(time) -
            _scrollController.position.viewportDimension / 3)
        .clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    if (!animate) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: AppMotion.base,
      curve: AppMotion.spring,
    );
  }

  void _jumpToNow(TimelineGeometry geometry) {
    ref.read(selectedDateProvider.notifier).jumpToToday();
    // The date change rebuilds the timeline; scroll after that frame so the
    // scroll extent belongs to the day we are actually landing on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(DateTime.now(), geometry);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final selectedDate = ref.watch(selectedDateProvider);
        final isToday = ref.watch(isViewingTodayProvider);
        final schedule = ref.watch(selectedDayPrayerScheduleProvider);
        final placedEntries = ref.watch(selectedDayTimelineProvider);
        final now = ref.watch(currentMinuteProvider);

        final geometry = TimelineGeometry(
          dayStart: selectedDate,
          hourExtent: windowSize.hourExtent,
        );

        if (!_hasPositionedInitially) {
          _hasPositionedInitially = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scrollTo(isToday ? DateTime.now() : selectedDate.add(const Duration(hours: 7)),
                  geometry, animate: false);
            }
          });
        }

        final padding = windowSize.pagePadding;

        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padding - 8, 8, padding - 8, 4),
                  child: DateNavigationHeader(dense: windowSize.isCompact),
                ),
                if (widget.showBanner)
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, 8, padding, 4),
                    child: const PrayerLockoutBanner(),
                  ),
                Expanded(
                  child: _SwipeableTimeline(
                    onPrevious: () =>
                        ref.read(selectedDateProvider.notifier).previousDay(),
                    onNext: () => ref.read(selectedDateProvider.notifier).nextDay(),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        12,
                        padding,
                        // Clears the FAB and the home indicator.
                        96 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: SizedBox(
                        height: geometry.totalExtent,
                        child: _TimelineCanvas(
                          geometry: geometry,
                          schedule: schedule,
                          placedEntries: placedEntries,
                          now: now,
                          showNowLine: isToday,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: padding,
              bottom: 20 + MediaQuery.paddingOf(context).bottom,
              child: _JumpToNowButton(onPressed: () => _jumpToNow(geometry)),
            ),
          ],
        );
      },
    );
  }
}

/// Horizontal drags flip to the previous/next day.
///
/// Uses a raw [GestureDetector] rather than a [PageView] because the
/// timeline is date-unbounded — a PageView would need a finite page count or
/// an infinite-scroll shim, and the vertical scroll would have to be nested
/// inside every page.
class _SwipeableTimeline extends StatelessWidget {
  const _SwipeableTimeline({
    required this.child,
    required this.onPrevious,
    required this.onNext,
  });

  final Widget child;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Minimum fling velocity, in logical px/s, before a horizontal drag
  /// counts as a day change. Set high enough that a diagonal scroll doesn't
  /// trigger it.
  static const double _flingThreshold = 320;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > _flingThreshold) {
          onPrevious();
        } else if (velocity < -_flingThreshold) {
          onNext();
        }
      },
      child: child,
    );
  }
}

/// The stacked timeline layers, sized to a full 24-hour day.
class _TimelineCanvas extends StatelessWidget {
  const _TimelineCanvas({
    required this.geometry,
    required this.schedule,
    required this.placedEntries,
    required this.now,
    required this.showNowLine,
  });

  final TimelineGeometry geometry;
  final DailyPrayerSchedule schedule;
  final List<PlacedTimelineEntry> placedEntries;
  final DateTime now;
  final bool showNowLine;

  /// Gap between side-by-side blocks in an overlapping cluster.
  static const double _columnGap = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth - geometry.gutterWidth;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            ..._prayerBands(context, contentWidth),
            ..._hourRules(context, constraints.maxWidth),
            ..._blocks(context, contentWidth),
            if (showNowLine)
              AnimatedPositioned(
                duration: AppMotion.base,
                curve: AppMotion.spring,
                top: geometry.offsetOf(now) - 4.5,
                left: 0,
                right: 0,
                child: CurrentTimeIndicator(
                  now: now,
                  gutterWidth: geometry.gutterWidth,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Tinted bands for each prayer's validity window, behind everything else.
  List<Widget> _prayerBands(BuildContext context, double contentWidth) {
    return [
      for (final window in schedule.timeWindows)
        Positioned(
          top: geometry.offsetOf(window.start),
          left: geometry.gutterWidth,
          width: contentWidth,
          height: geometry.offsetOf(window.end) - geometry.offsetOf(window.start),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.palette.prayerBandFill(window.prayer),
              border: Border(
                top: BorderSide(color: context.palette.prayerBandEdge(window.prayer)),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(
                  window.prayer.displayName.toUpperCase(),
                  style: context.typography.eyebrow(
                    color: context.palette.prayerHue(window.prayer).withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  /// Hour labels down the gutter with a hairline rule across the canvas.
  List<Widget> _hourRules(BuildContext context, double fullWidth) {
    return [
      for (var hour = 0; hour < TimelineGeometry.hoursPerDay; hour++)
        Positioned(
          top: hour * geometry.hourExtent,
          left: 0,
          width: fullWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: geometry.gutterWidth,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    formatHourLabel(hour),
                    textAlign: TextAlign.right,
                    style: context.typography.ui(
                      size: 11,
                      color: context.palette.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: context.palette.hairline,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _blocks(BuildContext context, double contentWidth) {
    return [
      for (final placed in placedEntries)
        Positioned(
          top: geometry.offsetOf(placed.entry.start),
          left: geometry.gutterWidth +
              (contentWidth / placed.columnCount) * placed.column,
          width: (contentWidth / placed.columnCount) - _columnGap,
          child: TimelineBlock(
            key: ValueKey(placed.entry.id),
            entry: placed.entry,
            height: geometry.extentBetween(placed.entry.start, placed.entry.end),
            isCurrent: showNowLine && placed.entry.containsTime(now),
            onTap: placed.entry.isReadOnly
                ? null
                : () => _openEntry(context, placed.entry),
          ),
        ),
    ];
  }

  void _openEntry(BuildContext context, TimelineEntry entry) {
    // Only task blocks are editable from the timeline today; schedule-item
    // editing lands with the schedule editor.
    if (entry is TaskEntry) {
      showTaskFormSheet(context, existing: entry.task);
    }
  }
}

/// Returns the timeline to today and the current moment.
class _JumpToNowButton extends StatelessWidget {
  const _JumpToNowButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Jump to now',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: context.palette.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: context.palette.shadow,
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhLight.crosshairSimple,
                  size: 15,
                  color: context.palette.accentBright,
                ),
                const SizedBox(width: 8),
                Text(
                  'Now',
                  style: context.typography.ui(size: 13, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
