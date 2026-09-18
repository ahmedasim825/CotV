
import 'dart:io' show Platform;

import 'package:cupertino_native_better/cupertino_native_better.dart';
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

  /// The SF Symbol the native tab bar draws this destination with.
  ///
  /// Names, not glyphs: the bar is a `UITabBar` on the other side of a
  /// platform channel, and it resolves these itself against whatever SF
  /// Symbols the running iOS ships. That is the point of using it — the icon
  /// set matches the rest of the system rather than approximating it, and it
  /// picks up the platform's own weight, scaling and selected-state fill for
  /// free.
  ///
  /// Only the compact iOS bar reads these. The sidebar and the Material bar
  /// keep [icon], because Phosphor is what the rest of the app draws with.
  String get sfSymbol {
    switch (this) {
      case AppDestination.home:
        return 'house';
      case AppDestination.tasks:
        return 'checklist';
      case AppDestination.study:
        return 'books.vertical';
      case AppDestination.food:
        return 'fork.knife';
      case AppDestination.prayers:
        return 'moon.stars';
      case AppDestination.settings:
        return 'gearshape';
    }
  }

  /// The filled counterpart, for the selected tab.
  ///
  /// `fork.knife` has no filled variant in SF Symbols, so it stands as it is
  /// — the tint change carries the state there.
  String get sfSymbolFilled {
    switch (this) {
      case AppDestination.home:
        return 'house.fill';
      case AppDestination.tasks:
        return 'checklist';
      case AppDestination.study:
        return 'books.vertical.fill';
      case AppDestination.food:
        return 'fork.knife';
      case AppDestination.prayers:
        return 'moon.stars.fill';
      case AppDestination.settings:
        return 'gearshape.fill';
    }
  }

  /// The same glyph, heavier.
  ///
  /// The floating nav bar swaps to this on the selected destination. Weight
  /// against outline is how the reference material marks selection, and it is
  /// the half that survives when the chip behind it is competing with the
  /// bar's own tint — a hue change alone reads as a recolour rather than as a
  /// position. See [PhBold] for why this is Bold and not Fill.
  IconData get selectedIcon {
    switch (this) {
      case AppDestination.home:
        return PhBold.house;
      case AppDestination.tasks:
        return PhBold.listChecks;
      case AppDestination.study:
        return PhBold.books;
      case AppDestination.food:
        return PhBold.bowlFood;
      case AppDestination.prayers:
        return PhBold.starAndCrescent;
      case AppDestination.settings:
        return PhBold.gear;
    }
  }
}

/// Whether SF Symbol names will resolve to glyphs rather than to nothing.
///
/// Off Apple platforms the tab bar falls back to a Flutter `CupertinoTabBar`,
/// and a `CNSymbol` handed to it has no font to come from — every tab renders
/// an empty placeholder circle. So the Phosphor glyph is supplied instead, and
/// the bar has icons everywhere.
///
/// Gated on `dart:io` rather than [ThemeData.platform], which is the rule
/// everywhere else in this file and is documented at [useLiquidGlass]. It has
/// to be, and the exception is the whole point: the package decides which of
/// its two paths to take from `Platform.isIOS` itself, so a gate reading the
/// theme would disagree with it exactly where the theme is faked — under
/// `flutter_test`, and in `tool/tasks_preview.dart`, which forces the iOS look
/// onto a Windows window. That disagreement is what puts the placeholders on
/// screen.
final bool _hasSFSymbols = Platform.isIOS || Platform.isMacOS;

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
/// timeline is gone. The dashboard, the prayer bento and the task list all
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

  /// Handed to the compact pane as its [PrimaryScrollController], so tapping
  /// the tab you are already on can send it back to the top the way every
  /// iOS tab bar does.
  ///
  /// One controller for all five panes is safe because only one is mounted at
  /// a time — but "safe" here rests on that staying true, so [_scrollToTop]
  /// checks rather than assumes. A controller with two attached positions
  /// throws the moment anything reads `.position`.
  final ScrollController _paneScroll = ScrollController();

  /// Which tab the bar should show as current.
  ///
  /// `settings` is a destination but not a tab — it opens from the header
  /// gear — so `indexOf` returns -1 for it. The native bar takes an index and
  /// has no "nothing selected" state, so that is clamped to Home rather than
  /// passed on: a `UITabBar` handed -1 selects nothing and draws no
  /// indicator at all.
  int get _navIndex {
    final int index = AppDestinationX.navItems.indexOf(_destination);
    return index < 0 ? 0 : index;
  }

  void _scrollToTop() {
    if (_paneScroll.positions.length != 1) return;
    final ScrollPosition position = _paneScroll.positions.first;
    if (position.pixels <= position.minScrollExtent) return;
    position.animateTo(
      position.minScrollExtent,
      duration: context.motion.base,
      curve: AppMotion.spring,
    );
  }

  @override
  void dispose() {
    _paneScroll.dispose();
    super.dispose();
  }

  void _select(AppDestination destination) {
    if (_destination == destination) {
      // The tab you are already on: go back to the top instead of rebuilding
      // the pane you are already looking at.
      _scrollToTop();
      return;
    }
    setState(() => _destination = destination);
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
                  // Only the compact pane. The rail layout has no tab to
                  // re-tap, and giving an iPad's two-column body a shared
                  // primary controller is how you end up with two
                  // positions attached to one controller.
                  : PrimaryScrollController(
                      controller: _paneScroll,
                      child: AppNavigation(
                        select: _select,
                        child: revealedPaneFor(_destination),
                      ),
                    ),
            ),
          ),
          // Lets the bar float over the panes rather than sitting in a strip
          // below them. Scaffold then reports the bar's own footprint as the
          // body's bottom padding, which is what every pane reads to know how
          // far to pad its scroll — no pane needs to know the bar's height.
          extendBody: context.useLiquidGlass,
          bottomNavigationBar: windowSize.usesNavigationRail
              ? null
              : context.useLiquidGlass
              ? CNTabBar(
                  items: [
                    for (final item in AppDestinationX.navItems)
                      CNTabBarItem(
                        label: item.label,
                        icon: _hasSFSymbols ? CNSymbol(item.sfSymbol) : null,
                        activeIcon: _hasSFSymbols
                            ? CNSymbol(item.sfSymbolFilled)
                            : null,
                        // Phosphor stands in where SF Symbols do not exist.
                        // The package renders `customIcon` itself, so this
                        // path works on every platform; it just gives up the
                        // system icon set where there is one to give up.
                        customIcon: _hasSFSymbols ? null : item.icon,
                        activeCustomIcon:
                            _hasSFSymbols ? null : item.selectedIcon,
                      ),
                  ],
                  // Clamped, because `settings` is reachable but is not a tab:
                  // it opens from the header gear, and `indexOf` would hand
                  // the bar a -1 and put it in no state at all.
                  currentIndex: _navIndex,
                  onTap: (index) =>
                      _select(AppDestinationX.navItems[index]),
                  tint: kPalette.accentBright,
                  // 16, against the 24 a bare `CNSymbol` defaults to and the
                  // 25 the custom-icon path uses. Apple's 25pt figure is for
                  // the classic edge-to-edge tab bar; the iOS 26 floating one
                  // is a shorter pill carrying the same glyph *and* a label in
                  // the same height, so the glyph has to give up the room.
                  //
                  // Arrived at on device rather than by reasoning: 24 read as
                  // packed, and so did 20 — measured off two screenshots, that
                  // step only moved the glyph 2.3pt because the label below it
                  // does not move. 16 is the first value where the glyph stops
                  // dominating the label.
                  //
                  // Set here rather than per symbol on purpose: the bar-level
                  // value takes precedence over `CNSymbol.size`, so this is
                  // the one number that moves both the SF Symbol path and the
                  // Phosphor fallback together.
                  iconSize: 16,
                )
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
