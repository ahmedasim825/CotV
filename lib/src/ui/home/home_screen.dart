import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../responsive/breakpoints.dart';
import '../shell/milo_dock.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/reveal_on_entrance.dart';
import 'widgets/agenda_card.dart';
import 'widgets/focus_tasks_card.dart';
import 'widgets/home_search_bar.dart';
import 'widgets/music_widget.dart';
import 'widgets/nutrition_card.dart';
import 'widgets/reminders_card.dart';
import 'widgets/study_breakdown_card.dart';
import 'widgets/welcome_header.dart';

/// The Home pane: a top strip over a bento of cards.
///
/// Layout and nothing else — every card reads its own providers, and each
/// renders a neutral line when it has nothing to show, which is the state a
/// fresh install is in.
///
/// **Two compositions off one file.** On Windows this is the desktop bento:
/// header beside the music widget, then a 2x2 of Tasks, Reminders, Study time
/// and Nutrition. On iOS it is the phone mock: a settings gear in the header,
/// the Milo block in the page, one merged Tasks / Reminders card, and no music
/// widget at all. The cards themselves are shared; only the arrangement and
/// the material differ, which is why this branches here rather than in any of
/// them.
///
/// No [Scaffold] here: [AppShell] supplies one, along with the background and
/// the Milo end drawer. Nesting a second would make the drawer unreachable
/// from anything calling `Scaffold.of(context)`.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const double _gap = 24;

  /// The widest the search bar and the Milo block are allowed to grow.
  ///
  /// Both are single controls rather than content, and a 1194pt iPad would
  /// otherwise stretch the pill across the whole pane and strand the orb in
  /// the middle of an empty band.
  static const double _centreColumnMax = 560;

  @override
  Widget build(BuildContext context) {
    final glass = context.useLiquidGlass;

    return AdaptiveLayout(
      builder: (context, windowSize) {
        final padding = windowSize.pagePadding;
        final twoUp = !windowSize.isCompact;

        final list = ListView(
          padding: EdgeInsets.fromLTRB(
            padding,
            16,
            padding,
            // Clears the floating nav pill, which the Scaffold reports as
            // bottom padding once `extendBody` puts the body underneath it.
            // Unconditional because it is zero on a desktop window, so this
            // costs nothing off iOS rather than needing a gate of its own.
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            RevealOnEntrance(
              child: _Header(glass: glass, twoUp: twoUp),
            ),
            const SizedBox(height: _gap),
            RevealOnEntrance(
              delay: const Duration(milliseconds: 60),
              // Inset and centred, per the mock, rather than spanning the
              // full pane edge to edge. Not `const` all the way down:
              // ConstrainedBox's constructor isn't const in this Flutter
              // version.
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _centreColumnMax),
                  child: const HomeSearchBar(),
                ),
              ),
            ),
            if (glass) ...[
              const SizedBox(height: _gap),
              RevealOnEntrance(
                delay: const Duration(milliseconds: 80),
                // A full-width band rather than a column of its own, at every
                // iOS width. The block is a ~180pt orb box; parked in the
                // right-hand column an iPad would otherwise give it, it leaves
                // a tall dead gap underneath.
                //
                // `showLabels: true` always — that flag means "the whole
                // block, not the collapsed orb", and there is no collapsed
                // Home. `EdgeInsets.zero` because the ListView above has
                // already applied the page gutter.
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _centreColumnMax,
                    ),
                    child: const MiloDock(
                      showLabels: true,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            if (glass) ...[
              const RevealOnEntrance(
                delay: Duration(milliseconds: 100),
                child: AgendaCard(),
              ),
              const SizedBox(height: _gap),
              RevealOnEntrance(
                delay: const Duration(milliseconds: 140),
                child: _CardRow(
                  twoUp: twoUp,
                  left: const StudyBreakdownCard(),
                  right: const NutritionCard(),
                ),
              ),
            ] else ...[
              RevealOnEntrance(
                delay: const Duration(milliseconds: 100),
                child: _CardRow(
                  twoUp: twoUp,
                  left: const FocusTasksCard(),
                  right: const RemindersCard(),
                ),
              ),
              const SizedBox(height: _gap),
              RevealOnEntrance(
                delay: const Duration(milliseconds: 140),
                child: _CardRow(
                  twoUp: twoUp,
                  left: const StudyBreakdownCard(),
                  right: const NutritionCard(),
                ),
              ),
            ],
          ],
        );

        // One backdrop capture per frame for every glass card on the page,
        // instead of one each: the cards declare `BackdropFilter.grouped`, and
        // this is the ancestor that makes that mean something. They never
        // overlap, so the grouped result is identical to what separate filters
        // would draw — only the cost differs, and it now scales with the
        // page's area rather than with how many cards are on it.
        //
        // The nav pill deliberately stays outside this group: it overlaps the
        // cards, and overlapping filters sharing a backdrop key render as
        // though only one of them applied.
        return glass ? BackdropGroup(child: list) : list;
      },
    );
  }
}

/// The greeting, plus whatever rides alongside it: the music widget on the
/// desktop, the settings gear on a phone.
class _Header extends StatelessWidget {
  const _Header({required this.glass, required this.twoUp});

  final bool glass;
  final bool twoUp;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      // The gear only appears where nothing else offers Settings. Past the
      // compact breakpoint the sidebar is mounted and its footer gear is
      // right there, so a second one in the header would be two doors to the
      // same room. Keyed off the window and not the device, because an iPad
      // in Slide Over is compact, loses that sidebar, and would otherwise
      // have no route to Settings at all.
      if (!twoUp) {
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: WelcomeHeader()),
            _SettingsGear(),
          ],
        );
      }
      return const WelcomeHeader();
    }

    return twoUp
        ? LayoutBuilder(
            builder: (context, constraints) {
              // A share of the row rather than a fixed width.
              //
              // The card wants to be wide — the transport sits beside the text
              // instead of under it, which is what keeps it short. But a fixed
              // 420 eats the greeting: "Welcome, Ahmed" is 42pt type and wraps
              // to two lines once it drops under about 380, which moves the
              // whole page down. So the card takes what is spare and gives way
              // when there is not enough.
              final width = (constraints.maxWidth * 0.45).clamp(320.0, 420.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: WelcomeHeader()),
                  const SizedBox(width: HomeScreen._gap),
                  SizedBox(width: width, child: const MusicWidget()),
                ],
              );
            },
          )
        : const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WelcomeHeader(),
              SizedBox(height: HomeScreen._gap),
              MusicWidget(),
            ],
          );
  }
}

/// The phone's way into Settings, in the corner the mock puts it.
///
/// Composed here rather than inside [WelcomeHeader], which has its own
/// overflow handling for the prayer-and-weather line under the greeting and a
/// test pinning it at double text scale. Wrapping that in a new Row is how
/// you break it.
class _SettingsGear extends StatelessWidget {
  const _SettingsGear();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Settings',
      child: InkWell(
        onTap: () =>
            AppNavigation.maybeOf(context)?.call(AppDestination.settings),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: minTouchTarget,
          height: minTouchTarget,
          child: Icon(
            PhLight.gear,
            size: 21,
            color: context.palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Two cards side by side, or stacked when the pane is too narrow to give
/// each one a readable width.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.twoUp,
    required this.left,
    required this.right,
  });

  final bool twoUp;

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (!twoUp) {
      return Column(
        children: [
          left,
          const SizedBox(height: HomeScreen._gap),
          right,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: HomeScreen._gap),
          Expanded(child: right),
        ],
      ),
    );
  }
}
