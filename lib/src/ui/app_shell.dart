import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_session_providers.dart';
import '../providers/milo_providers.dart';
import '../providers/study_providers.dart';
import '../providers/sync_providers.dart';
import 'food/food_search_screen.dart';
import 'home/home_screen.dart';
import 'milo/milo_assistant_screen.dart';
import 'prayers/prayers_screen.dart';
import 'responsive/breakpoints.dart';
import 'settings/settings_screen.dart';
import 'shell/milo_dock.dart';
import 'shell/sidebar.dart';
import 'shell/window_chrome.dart';
import 'study/study_screen.dart';
import 'tasks/task_list_view.dart';
import 'theme/app_theme.dart';
import 'widgets/ph_light_icons.dart';
import 'widgets/reveal_on_entrance.dart';

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

/// A way for anything under the shell to move to another destination.
///
/// The current destination is [AppShell]'s own state, so a dashboard card that
/// wants to open the Tasks screen cannot set it directly. Rather than lift the
/// whole thing into a provider — which the sidebar, the bottom bar and their
/// tests all read — the shell hands its selector down the tree.
class AppNavigation extends InheritedWidget {
  const AppNavigation({super.key, required this.select, required super.child});

  final ValueChanged<AppDestination> select;

  /// Null outside an [AppShell] — a card pumped on its own in a test, which
  /// should render rather than throw.
  static ValueChanged<AppDestination>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppNavigation>()?.select;

  @override
  bool updateShouldNotify(AppNavigation oldWidget) =>
      select != oldWidget.select;
}

/// The pane a destination renders.
/// The destinations that stage their own entrance, section by section.
///
/// Wrapping these in a second [RevealOnEntrance] would fade the whole pane in
/// underneath their own stagger, which reads as a double take.
const Set<AppDestination> _selfRevealing = {
  AppDestination.home,
  AppDestination.prayers,
};

/// [paneFor], plus the entrance animation for the panes that lack one.
///
/// Keyed by destination so the reveal replays on every switch. Without the key
/// the state outlives the swap — same widget type, same slot — and the
/// animation would run once, on the first tab visited, and never again.
Widget revealedPaneFor(AppDestination destination) {
  final Widget pane = paneFor(destination);
  if (_selfRevealing.contains(destination)) return pane;
  return RevealOnEntrance(key: ValueKey(destination), child: pane);
}

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

  /// Opens and closes the rail, from the control in `WindowChrome`.
  ///
  /// There is no longer a second control toggling [SidebarMode.collapsed] —
  /// see that value's doc.
  void _toggleHidden() => setState(() {
    _sidebarMode = _sidebarMode == SidebarMode.hidden
        ? SidebarMode.expanded
        : SidebarMode.hidden;
  });

  @override
  Widget build(BuildContext context) {
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

    // And once more for sync's scheduler, which owns every trigger: the
    // pull on sign-in, the one on resume, the debounce after a local write
    // and the five-minute poll. A no-op signed out or in a build with no
    // Supabase defines.
    ref.watch(syncSchedulerProvider);

    return AdaptiveLayout(
      builder: (context, windowSize) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          endDrawer: const MiloAssistantScreen(),
          // Explicit, because the panel is glass now and samples whatever is
          // behind it. Material's default black-54 leaves the dashboard
          // legible through the transcript; the palette's own scrim does not.
          drawerScrimColor: context.palette.scrim,
          // The launcher is the only way in. The right-edge drag that
          // would otherwise open the drawer starts inside the same 20pt
          // strip the task rows use to swipe away, so it would take that
          // gesture rather than share it.
          endDrawerEnableOpenDragGesture: false,
          body: _WithWindowChrome(
            // The rail runs up behind the title bar, so the strip needs its
            // current width to know how far to carry the fill.
            railWidth: windowSize.usesNavigationRail ? _sidebarMode.width : 0,
            onToggleSidebar: _toggleHidden,
            sidebarIsHidden: _sidebarMode == SidebarMode.hidden,
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
                                // Null on iOS: the Home pane shows the block
                                // itself there, and two orbs breathing at once
                                // on an iPad would read as two Milos.
                                dock: context.useLiquidGlass
                                    ? null
                                    : MiloDock(
                                        showLabels: _sidebarMode.showsLabels,
                                      ),
                              ),
                            Expanded(
                              child: AppNavigation(
                                select: _select,
                                child: revealedPaneFor(_destination),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : AppNavigation(
                      select: _select,
                      child: revealedPaneFor(_destination),
                    ),
            ),
          ),
          // Lets the pill float over the panes rather than sitting in a strip
          // below them. Scaffold then reports the pill's own footprint as the
          // body's bottom padding, which is what every pane reads to know how
          // far to pad its scroll — no pane needs to know the pill's height.
          extendBody: context.useLiquidGlass,
          bottomNavigationBar: windowSize.usesNavigationRail
              ? null
              : context.useLiquidGlass
              ? _LiquidGlassNavBar(destination: _destination, onSelect: _select)
              : _BottomNavBar(destination: _destination, onSelect: _select),
        );
      },
    );
  }
}

/// Reserves and draws the window chrome on a build whose window has none.
///
/// A no-op everywhere but Windows, where the runner reports the whole window
/// as client area and there is no caption left to move, minimise or close the
/// window with.
///
/// The inset is published as [MediaQuery] padding rather than applied as a
/// [Padding], so the [SafeArea] the shell already has consumes it and every
/// pane clears the strip without any of them knowing the strip exists — the
/// same trick `extendBody` uses at the other end of the window.
class _WithWindowChrome extends StatelessWidget {
  const _WithWindowChrome({
    required this.child,
    required this.onToggleSidebar,
    required this.sidebarIsHidden,
    required this.railWidth,
  });

  final Widget child;
  final VoidCallback onToggleSidebar;
  final bool sidebarIsHidden;

  /// How far the rail's fill carries across the chrome strip. Zero when the
  /// rail is hidden, or on a layout that has no rail at all.
  final double railWidth;

  @override
  Widget build(BuildContext context) {
    if (!context.useCustomWindowChrome) return child;

    final media = MediaQuery.of(context);

    return Stack(
      children: [
        MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(top: windowChromeHeight),
          ),
          child: child,
        ),
        // Under the buttons but over the panes: an 8pt grab band all the way
        // round, because the caption is not the only thing removing the
        // non-client area cost us — the resize edges went with it.
        const Positioned.fill(child: WindowResizeBorders()),
        // The rail's fill, carried up through the chrome strip so the rail
        // reads as one column from the top edge of the window rather than
        // starting below the title bar. Painted here because the rail itself
        // sits inside the [SafeArea] that reserves that strip, so it cannot
        // reach it. Animated on the rail's own curve so the two stay in step
        // while it opens and closes.
        Positioned(
          top: 0,
          left: 0,
          child: AnimatedContainer(
            duration: context.motion.fast,
            curve: AppMotion.spring,
            width: railWidth,
            height: windowChromeHeight,
            decoration: BoxDecoration(
              color: kRailFill,
              border: Border(
                right: BorderSide(color: context.palette.hairline),
              ),
            ),
          ),
        ),
        // Over the pane *and* the sidebar both, so the strip spans the window
        // the way the caption it replaces did. Last, so the three buttons win
        // over the top and corner grab bands they sit inside.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: WindowChrome(
            onToggleSidebar: onToggleSidebar,
            sidebarIsHidden: sidebarIsHidden,
          ),
        ),
      ],
    );
  }
}

/// The iOS bar: a capsule of glass floating over the pane, blurring whatever
/// scrolls beneath it.
///
/// **Five destinations, and nothing else.** Settings moved to the gear in the
/// Home header, and Milo moved into the Home pane — so this iterates
/// [AppDestinationX.navItems], which is already exactly those five, rather
/// than `AppDestination.values` plus a launcher the way [_BottomNavBar] does.
/// That does mean Milo is reachable from Home alone on iOS; the wake word,
/// armed by the shell for the life of the app, is what still reaches it from
/// anywhere else.
///
/// Its [BackdropFilter] is deliberately **not** `.grouped`. The pill overlaps
/// the scrolling content by definition — that is what `extendBody` is for —
/// and two overlapping filters sharing a backdrop key draw as though only one
/// of them applied.
class _LiquidGlassNavBar extends StatelessWidget {
  const _LiquidGlassNavBar({required this.destination, required this.onSelect});

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  /// The capsule's own height. 48pt of touch target with 4pt of breathing
  /// room above and below it.
  static const double _height = 56;

  /// How far the capsule is inset from the pane's edges. Less than the 20pt
  /// content gutter, so it reads as floating over the column rather than
  /// ruled to it.
  static const double _inset = 16;

  /// Stops the capsule stretching across an iPad. Five glyphs spread over
  /// 1100pt would put a finger's travel between neighbours.
  static const double _maxWidth = 420;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(_height / 2);

    // Apple's floating bars sit *inside* the home-indicator strip, not above
    // it — reserving the full 34pt leaves an obvious dead band under the
    // capsule. On a device with no indicator the subtraction floors at 10.
    final double lift = math.max(10, MediaQuery.paddingOf(context).bottom - 12);

    // `alphaBlend` of the card's fill with itself: the pill is a control laid
    // over live, moving content and needs more separation than a card resting
    // on the ground does. Arithmetic rather than a new token, because there is
    // one surface in the app that wants this and it is this one.
    final Color fill = Color.alphaBlend(palette.glassFill, palette.glassFill);

    return Padding(
      padding: EdgeInsets.fromLTRB(_inset, 0, _inset, lift),
      // `Align` with a heightFactor, not `Center`. Scaffold hands the bottom
      // bar loose constraints — max height the whole screen — and a bare
      // Center takes all of it, which floats the capsule in the middle of the
      // page instead of at the foot of it. heightFactor: 1 shrink-wraps the
      // capsule's own height while still centring it across the width.
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: DecoratedBox(
            // Outside the clip, so the shadow falls on the page rather than
            // being clipped away with the blur.
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  height: _height,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: palette.hairline),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.alphaBlend(palette.glassSpecular, fill),
                        fill,
                      ],
                      stops: const [0.0, 0.45],
                    ),
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border(
                      top: BorderSide(color: palette.innerHighlight),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (final item in AppDestinationX.navItems)
                        _GlassNavItem(
                          destination: item,
                          isSelected: item == destination,
                          onTap: () => onSelect(item),
                        ),
                    ],
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

/// One destination in the glass pill.
///
/// Selection reads two ways at once, as it does in the sidebar, because on a
/// blurred violet-tinted ground neither signal is strong enough alone. The
/// [_BottomNavBar]'s `accentSoft` pill — the accent at 16% — all but vanishes
/// against a backdrop already carrying the accent, so it is replaced here by a
/// second, brighter pane of glass inset in the first: the same move iOS makes
/// for a selected tab. The glyph then goes `accentBright`, not `accent`, for
/// the reason recorded on [_BottomNavItem] — at this size #7005BB is under
/// WCAG AA on this ground.
class _GlassNavItem extends StatelessWidget {
  const _GlassNavItem({
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
              height: _LiquidGlassNavBar._height,
              child: Center(
                child: AnimatedContainer(
                  duration: context.motion.fast,
                  curve: AppMotion.spring,
                  width: 46,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? palette.glassFill : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? palette.glassBorder
                          : Colors.transparent,
                    ),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    destination.icon,
                    size: 21,
                    color: isSelected
                        ? palette.accentBright
                        : palette.textMuted,
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
          const _MiloLauncherButton(),
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
                    color: isSelected ? palette.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    destination.icon,
                    size: 21,
                    color: isSelected
                        ? palette.accentBright
                        : palette.textMuted,
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

/// The phone bar's way into Milo.
///
/// This is an *action*, not a destination: it has no selected/unselected
/// state, never carries the pill or underline treatment [_BottomNavItem]
/// uses for the active row, and doesn't join [AppDestination] — tapping it
/// opens the end drawer in place, it doesn't navigate anywhere. It exists
/// because [MiloDock] (the sidebar's own entry point) mounts only past the
/// navigation-rail breakpoint; below that, this button is the only way to
/// reach Milo at all, the same job the deleted `QuickActionsGrid`'s
/// "Talk to Milo" pill used to do — same glyph, so it reads as the same
/// affordance moved rather than a new one invented.
///
/// Same 48pt touch target and [Expanded] footprint as [_BottomNavItem], so
/// the row stays even with it in the mix.
class _MiloLauncherButton extends StatelessWidget {
  const _MiloLauncherButton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Expanded(
      child: Semantics(
        button: true,
        label: 'Milo',
        child: Tooltip(
          message: 'Milo',
          child: GestureDetector(
            onTap: () => Scaffold.of(context).openEndDrawer(),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 48,
              child: Center(
                child: Icon(
                  PhLight.sparkle,
                  size: 21,
                  // textMuted, matching an unselected _BottomNavItem — not
                  // accentBright. accentBright is _BottomNavItem's signal for
                  // "this is where you are"; this button is an action, not a
                  // destination, and must not borrow the colour that means
                  // nav state. Settings sits immediately to this button's
                  // left, so if this read accentBright, selecting Settings
                  // would put two accentBright icons side by side — exactly
                  // the ambiguity to avoid. Not palette.accent either — at
                  // this size, on this ground, that token is under WCAG AA.
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
