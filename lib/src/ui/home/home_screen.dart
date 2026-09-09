import 'package:flutter/material.dart';

import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../widgets/prayer_lockout_banner.dart';
import '../widgets/reveal_on_entrance.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/focus_tasks_card.dart';
import 'widgets/next_prayer_card.dart';
import 'widgets/nutrition_card.dart';
import 'widgets/quick_actions_grid.dart';
import 'widgets/streak_bar.dart';
import 'widgets/study_breakdown_card.dart';

/// The Home tab: Milo, the day's headline numbers, and the shortcuts into
/// the rest of the app.
///
/// Every card reads its own providers, so this file is layout and nothing
/// else. Each of them also renders a neutral line when it has nothing to
/// show — a dashboard whose only honest answer is "nothing yet" has to be
/// able to say so, which is the state it is in on a fresh install.
///
/// No [Scaffold] here on purpose: [AppShell] already supplies one, along
/// with the ambient background and the Milo end drawer. Nesting a second
/// Scaffold would make [QuickActionsGrid]'s `Scaffold.of(context)` resolve
/// to a drawerless one and throw when "Talk to Milo" is tapped — which is
/// now the only way into Milo from this screen, since the floating launcher
/// that used to sit over the bottom-left corner has been removed.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final padding = windowSize.pagePadding;
        // Two columns once the pane can give each one a readable width; the
        // rings and macro bars start to crowd below roughly 340pt a side.
        final twoUp = !windowSize.isCompact;

        // Every glass card below samples the same backdrop — the ambient
        // canvas behind the pane — so they are grouped and it is sampled
        // once for the screen rather than once per card. Without this the
        // column of them costs a blur each.
        return BackdropGroup(
          child: ListView(
            // 32 at the bottom, not the 96 this used to reserve: the
            // floating Milo launcher that strip was clearing is gone, so the
            // content runs to the bottom bar with an ordinary margin under
            // it.
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 32),
            children: [
              const PrayerLockoutBanner(),
              const SizedBox(height: 12),
              RevealOnEntrance(
                child: DashboardHeader(
                  orbDiameter: windowSize.isCompact ? 124 : 148,
                ),
              ),
              const SizedBox(height: 28),
              const RevealOnEntrance(
                delay: Duration(milliseconds: 60),
                child: StreakBar(),
              ),
              const SizedBox(height: 20),
              const RevealOnEntrance(
                delay: Duration(milliseconds: 100),
                child: NextPrayerCard(),
              ),
              const SizedBox(height: 16),
              const RevealOnEntrance(
                delay: Duration(milliseconds: 140),
                child: FocusTasksCard(),
              ),
              const SizedBox(height: 16),
              RevealOnEntrance(
                delay: const Duration(milliseconds: 180),
                child: twoUp
                    ? const IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: StudyBreakdownCard()),
                            SizedBox(width: 16),
                            Expanded(child: NutritionCard()),
                          ],
                        ),
                      )
                    : const Column(
                        children: [
                          StudyBreakdownCard(),
                          SizedBox(height: 16),
                          NutritionCard(),
                        ],
                      ),
              ),
              const SizedBox(height: 28),
              const RevealOnEntrance(
                delay: Duration(milliseconds: 220),
                child: SectionHeader(
                  eyebrow: 'SHORTCUTS',
                  title: 'Quick actions',
                  titleSize: 22,
                ),
              ),
              const SizedBox(height: 14),
              const RevealOnEntrance(
                delay: Duration(milliseconds: 260),
                child: QuickActionsGrid(),
              ),
            ],
          ),
        );
      },
    );
  }
}
