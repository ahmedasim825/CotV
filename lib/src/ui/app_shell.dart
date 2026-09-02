import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/focus_session_providers.dart';
import 'focus/focus_session_overlay.dart';
import 'habits/habit_screen.dart';
import 'home_screen.dart';
import 'journal/journal_screen.dart';
import 'responsive/breakpoints.dart';
import 'schedule/daily_schedule_view.dart';
import 'settings/settings_screen.dart';
import 'tasks/task_list_view.dart';
import 'theme/app_theme.dart';
import 'widgets/ambient_background.dart';
import 'widgets/ph_light_icons.dart';
import 'widgets/prayer_lockout_banner.dart';

/// Top-level destinations.
enum AppDestination { schedule, tasks, habits, journal, prayers, settings }

extension AppDestinationX on AppDestination {
  String get label {
    switch (this) {
      case AppDestination.schedule:
        return 'Schedule';
      case AppDestination.tasks:
        return 'Tasks';
      case AppDestination.habits:
        return 'Habits';
      case AppDestination.journal:
        return 'Journal';
      case AppDestination.prayers:
        return 'Prayers';
      case AppDestination.settings:
        return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case AppDestination.schedule:
        return PhLight.calendarBlank;
      case AppDestination.tasks:
        return PhLight.listChecks;
      case AppDestination.habits:
        return PhLight.target;
      case AppDestination.journal:
        return PhLight.notePencil;
      case AppDestination.prayers:
        return PhLight.mosque;
      case AppDestination.settings:
        return PhLight.gear;
    }
  }

  /// Whether this destination can share the screen with another one.
  ///
  /// Only the timeline and the task list read well at half width; the
  /// prayer bento, the habit grid, the journal and settings are already
  /// multi-column or long-form layouts and take the full pane instead.
  bool get sharesSplitView =>
      this == AppDestination.schedule || this == AppDestination.tasks;
}

/// The pane a destination renders.
Widget paneFor(AppDestination destination) {
  switch (destination) {
    case AppDestination.schedule:
      return const DailyScheduleView();
    case AppDestination.tasks:
      return const TaskListView();
    case AppDestination.habits:
      return const HabitScreen();
    case AppDestination.journal:
      return const JournalScreen();
    case AppDestination.prayers:
      return const HomeScreen();
    case AppDestination.settings:
      return const SettingsScreen();
  }
}

/// The app's adaptive root.
///
/// Three layouts off one navigation state:
///   * **compact** (iPhone, iPad Slide Over) — one pane, bottom navigation.
///   * **medium** (iPad portrait) — one pane, navigation rail.
///   * **expanded** (iPad landscape) — schedule and tasks side by side with
///     a shared lockout banner above them.
///
/// The banner is hoisted out of the panes in split view so it isn't
/// duplicated; both child views take a flag for that rather than reaching
/// for the window size themselves.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppDestination _destination = AppDestination.schedule;

  void _select(AppDestination destination) {
    if (_destination != destination) {
      setState(() => _destination = destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A running focus session replaces the whole shell — that is the point
    // of it.
    final session = ref.watch(focusSessionProvider);
    if (session != null) {
      return FocusSessionOverlay(session: session);
    }

    return AdaptiveLayout(
      builder: (context, windowSize) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AmbientBackground(
            child: SafeArea(
              // The bottom bar draws its own home-indicator padding, so the
              // body must not also reserve it.
              bottom: false,
              child: windowSize.usesNavigationRail
                  ? _RailLayout(
                      windowSize: windowSize,
                      destination: _destination,
                      onSelect: _select,
                    )
                  : paneFor(_destination),
            ),
          ),
          bottomNavigationBar: windowSize.usesNavigationRail
              ? null
              : _BottomNavBar(
                  destination: _destination,
                  onSelect: _select,
                ),
        );
      },
    );
  }
}

/// Navigation rail plus content, splitting into two panes when wide enough.
class _RailLayout extends StatelessWidget {
  const _RailLayout({
    required this.windowSize,
    required this.destination,
    required this.onSelect,
  });

  final WindowSize windowSize;
  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _NavigationSidebar(destination: destination, onSelect: onSelect),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: context.palette.hairline,
        ),
        Expanded(
          child: windowSize.usesSplitView && destination.sharesSplitView
              ? _SplitPanes(destination: destination)
              : paneFor(destination),
        ),
      ],
    );
  }
}

/// Master-detail: the timeline beside the task list, with the prayer status
/// banner shared above both.
class _SplitPanes extends StatelessWidget {
  const _SplitPanes({required this.destination});

  final AppDestination destination;

  /// The timeline gets the larger share: it is the denser of the two and
  /// degrades faster when narrowed.
  static const int _scheduleFlex = 6;
  static const int _tasksFlex = 5;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(40, 16, 40, 0),
          child: PrayerLockoutBanner(),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(
                flex: _scheduleFlex,
                child: DailyScheduleView(showBanner: false),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: context.palette.hairline,
              ),
              const Expanded(flex: _tasksFlex, child: TaskListView()),
            ],
          ),
        ),
      ],
    );
  }
}

/// The iPad sidebar.
class _NavigationSidebar extends StatelessWidget {
  const _NavigationSidebar({required this.destination, required this.onSelect});

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 92,
      padding: EdgeInsets.only(
        top: 20,
        bottom: 20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: palette.accentBright,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 28),
          // Six destinations no longer fit a short iPad in landscape, so the
          // rail scrolls rather than overflowing.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final item in AppDestination.values) ...[
                    _RailItem(
                      destination: item,
                      isSelected: item == destination,
                      onTap: () => onSelect(item),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.spring,
                width: 48,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? palette.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  destination.icon,
                  size: 20,
                  color: isSelected ? palette.accentBright : palette.textMuted,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.typography.ui(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: isSelected ? palette.textPrimary : palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The iPhone bottom bar. Draws its own bottom padding so the row sits above
/// the home indicator on a Dynamic Island device.
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.destination, required this.onSelect});

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final item in AppDestination.values)
            _BottomNavItem(
              destination: item,
              isSelected: item == destination,
              onTap: () => onSelect(item),
            ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: destination.label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            // 48pt keeps the target comfortably above Apple's 44pt minimum.
            height: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  destination.icon,
                  size: 21,
                  color: isSelected ? palette.accentBright : palette.textMuted,
                ),
                const SizedBox(height: 4),
                Padding(
                  // Six labels across a 393pt phone leaves ~65pt each; the
                  // clamp keeps "Schedule" from colliding with "Tasks".
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.typography.ui(
                      size: 10,
                      weight: FontWeight.w600,
                      color:
                          isSelected ? palette.textPrimary : palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
