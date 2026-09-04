import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/focus_session_providers.dart';
import '../providers/study_providers.dart';
import 'focus/focus_session_overlay.dart';
import 'habits/habit_screen.dart';
import 'home_screen.dart';
import 'journal/journal_screen.dart';
import '../providers/milo_providers.dart';
import 'milo/milo_assistant_screen.dart';
import 'responsive/breakpoints.dart';
import 'schedule/daily_schedule_view.dart';
import 'settings/settings_screen.dart';
import 'study/study_screen.dart';
import 'tasks/task_list_view.dart';
import 'theme/app_theme.dart';
import 'widgets/ambient_background.dart';
import 'widgets/ph_light_icons.dart';
import 'widgets/prayer_lockout_banner.dart';

/// Top-level destinations.
enum AppDestination {
  schedule,
  tasks,
  habits,
  study,
  journal,
  prayers,
  settings
}

extension AppDestinationX on AppDestination {
  String get label {
    switch (this) {
      case AppDestination.schedule:
        return 'Schedule';
      case AppDestination.tasks:
        return 'Tasks';
      case AppDestination.habits:
        return 'Habits';
      case AppDestination.study:
        return 'Study';
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
      case AppDestination.study:
        return PhLight.timer;
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
    case AppDestination.study:
      return const StudyScreen();
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

    // Watched here, and only here, because a Riverpod notifier that nothing
    // listens to is never constructed — so its build() never runs and the
    // microphone is never armed. The shell outlives the Milo panel, which
    // is what lets the wake word work with the panel closed.
    ref.watch(wakeWordProvider);

    // Same reason, different failure: StudyNotifier reconciles a session
    // left behind by a kill in its build(). Watched from the shell so that
    // happens on launch, rather than the first time the user happens to
    // open the Study tab — the notification for that session has already
    // fired, and the log has to exist by the time they look for it.
    ref.watch(studyProvider);

    // Registering the App Intents needs the same treatment: iOS only shows
    // a shortcut it has been told about, and nothing else in the app reads
    // this provider, so without a watch it would never run. A no-op off
    // iOS.
    ref.watch(studyAppIntentsProvider);

    return AdaptiveLayout(
      builder: (context, windowSize) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          endDrawer: const MiloAssistantScreen(),
          // The launcher is the only way in. The right-edge drag that
          // would otherwise open the drawer starts inside the same 20pt
          // strip the timeline uses to change days and the task and
          // journal rows use to swipe away, so it would take those
          // gestures rather than share them.
          endDrawerEnableOpenDragGesture: false,
          body: AmbientBackground(
            child: SafeArea(
              // The bottom bar draws its own home-indicator padding, so the
              // body must not also reserve it.
              bottom: false,
              child: Stack(
                children: [
                  windowSize.usesNavigationRail
                      ? _RailLayout(
                          windowSize: windowSize,
                          destination: _destination,
                          onSelect: _select,
                        )
                      : paneFor(_destination),
                  Positioned(
                    // Clears the rail when there is one, and sits opposite
                    // each screen's own quick-add pill on the right.
                    left: windowSize.usesNavigationRail
                        ? _NavigationSidebar.width + windowSize.pagePadding
                        : windowSize.pagePadding,
                    bottom: 20 + MediaQuery.paddingOf(context).bottom,
                    child: const MiloLauncher(),
                  ),
                ],
              ),
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

  /// Also the offset the Milo launcher clears in rail layouts.
  static const double width = 92;

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: width,
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
          // Seven destinations no longer fit a short iPad in landscape, so
          // the rail scrolls rather than overflowing. Labels stay here —
          // the rail has the width for them, and it is the surface where a
          // destination's name is worth the space.
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
                duration: context.motion.fast,
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

/// One destination in the phone bar.
///
/// Icon-only. Six labels across a 393pt phone already left ~65pt each and
/// ellipsised "Schedule"; a seventh makes them unreadable, and a truncated
/// label names a destination no better than its glyph does.
///
/// The label is not dropped, only moved: it stays the [Semantics] label, so
/// screen readers are unaffected, and becomes a [Tooltip], so a long press
/// (or a hover on desktop) still names the destination. A selected item is
/// marked with a pill behind the glyph, taking over the job the label
/// colour used to do.
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
        child: Tooltip(
          message: destination.label,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              // 48pt keeps the target comfortably above Apple's 44pt
              // minimum.
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: context.motion.fast,
                  curve: AppMotion.spring,
                  width: 46,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? palette.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    destination.icon,
                    size: 21,
                    color:
                        isSelected ? palette.accentBright : palette.textMuted,
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
