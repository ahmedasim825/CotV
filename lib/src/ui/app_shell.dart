import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_session_providers.dart';
import '../providers/focus_session_providers.dart';
import '../providers/milo_providers.dart';
import '../providers/study_providers.dart';
import 'focus/focus_session_overlay.dart';
import 'food/food_search_screen.dart';
import 'home/home_screen.dart';
import 'milo/milo_assistant_screen.dart';
import 'prayers/prayers_screen.dart';
import 'responsive/breakpoints.dart';
import 'settings/settings_screen.dart';
import 'shell/sidebar.dart';
import 'study/study_screen.dart';
import 'tasks/task_list_view.dart';
import 'theme/app_theme.dart';
import 'widgets/ambient_background.dart';
import 'widgets/ph_light_icons.dart';

/// Top-level destinations.
enum AppDestination { home, tasks, study, food, prayers, settings }

extension AppDestinationX on AppDestination {
  /// The five that appear as rows in the sidebar. Settings is reached from
  /// the footer gear instead, which is where the design puts it.
  static const List<AppDestination> navItems = [
    AppDestination.home,
    AppDestination.tasks,
    AppDestination.study,
    AppDestination.food,
    AppDestination.prayers,
  ];

  String get label {
    switch (this) {
      case AppDestination.home:
        return 'Home';
      case AppDestination.tasks:
        return 'Tasks';
      case AppDestination.study:
        return 'Study';
      case AppDestination.food:
        return 'Food';
      case AppDestination.prayers:
        return 'Prayers';
      case AppDestination.settings:
        return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case AppDestination.home:
        return PhLight.house;
      case AppDestination.tasks:
        return PhLight.listChecks;
      case AppDestination.study:
        return PhLight.books;
      case AppDestination.food:
        return PhLight.bowlFood;
      case AppDestination.prayers:
        return PhLight.starAndCrescent;
      case AppDestination.settings:
        return PhLight.gear;
    }
  }
}

/// The pane a destination renders.
Widget paneFor(AppDestination destination) {
  switch (destination) {
    case AppDestination.home:
      return const HomeScreen();
    case AppDestination.tasks:
      return const TaskListView();
    case AppDestination.study:
      return const StudyScreen();
    case AppDestination.food:
      return const FoodSearchScreen();
    case AppDestination.prayers:
      return const PrayersScreen();
    case AppDestination.settings:
      return const SettingsScreen();
  }
}

/// The app's adaptive root.
///
/// Two layouts off one navigation state:
///   * **compact** (iPhone, iPad Slide Over) — one pane, bottom navigation.
///   * **medium and expanded** (iPad, desktop) — one pane, navigation rail.
///
/// Every destination takes the full pane. There is no split view: the two
/// halves it used to pair were the timeline and the task list, and the
/// timeline is gone. The dashboard, the prayer bento and the habit grid all
/// widen into their own multi-column layouts instead, which reads better
/// than two unrelated screens sharing a window.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppDestination _destination = AppDestination.home;
  SidebarMode _sidebarMode = SidebarMode.expanded;

  void _select(AppDestination destination) {
    if (_destination != destination) {
      setState(() => _destination = destination);
    }
  }

  void _toggleCollapse() => setState(() {
        _sidebarMode = _sidebarMode == SidebarMode.expanded
            ? SidebarMode.collapsed
            : SidebarMode.expanded;
      });

  void _toggleHidden() => setState(() {
        _sidebarMode = _sidebarMode == SidebarMode.hidden
            ? SidebarMode.expanded
            : SidebarMode.hidden;
      });

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

    // And the same again for the one-time move of the pre-threads
    // transcript into a session: it has to happen whether or not the user
    // ever opens the Milo panel, and a provider nothing watches never runs.
    ref.watch(chatImportProvider);

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
          // strip the task rows use to swipe away, so it would take that
          // gesture rather than share it.
          endDrawerEnableOpenDragGesture: false,
          body: AmbientBackground(
            child: SafeArea(
              // The bottom bar draws its own home-indicator padding, so the
              // body must not also reserve it.
              bottom: false,
              // The pane owns the whole body. There used to be a Stack here
              // with a floating Milo launcher pinned to the bottom-left
              // corner of every screen; it obstructed the content behind it
              // and forced each screen to reserve a strip of dead padding to
              // clear it, for an entry point the dashboard's "Talk to Milo"
              // quick action already provided. The end drawer below is
              // unchanged — only the pill that opened it is gone.
              child: windowSize.usesNavigationRail
                  ? Stack(
                      children: [
                        Row(
                          children: [
                            if (_sidebarMode != SidebarMode.hidden)
                              Sidebar(
                                mode: _sidebarMode,
                                destination: _destination,
                                onSelect: _select,
                                onToggleCollapse: _toggleCollapse,
                                onToggleHidden: _toggleHidden,
                              ),
                            Expanded(child: paneFor(_destination)),
                          ],
                        ),
                        // The only way back once the sidebar is hidden — it
                        // has no other footprint to click on.
                        if (_sidebarMode == SidebarMode.hidden)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Tooltip(
                              message: 'Show sidebar',
                              child: Material(
                                color: context.palette.surfaceRaised,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: _toggleHidden,
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: minTouchTarget,
                                    height: minTouchTarget,
                                    child: Icon(PhLight.sidebarSimple,
                                        size: 20,
                                        color: context.palette.textSecondary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
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
/// Icon-only. Seven labels across a 393pt phone leave ~56pt each, which
/// ellipsises the longer ones — and a truncated label names a destination no
/// better than its glyph does. The 46pt selection pill and the 48pt touch
/// target still fit inside that.
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
