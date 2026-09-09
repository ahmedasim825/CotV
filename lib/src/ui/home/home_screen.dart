import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../widgets/reveal_on_entrance.dart';
import 'widgets/focus_tasks_card.dart';
import 'widgets/home_search_bar.dart';
import 'widgets/music_widget.dart';
import 'widgets/nutrition_card.dart';
import 'widgets/reminders_card.dart';
import 'widgets/study_breakdown_card.dart';
import 'widgets/welcome_header.dart';

/// The Home pane: a top strip over a 2x2 bento.
///
/// Layout and nothing else — every card reads its own providers, and each
/// renders a neutral line when it has nothing to show, which is the state a
/// fresh install is in.
///
/// No [Scaffold] here: [AppShell] supplies one, along with the background and
/// the Milo end drawer. Nesting a second would make the drawer unreachable
/// from anything calling `Scaffold.of(context)`.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const double _gap = 20;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final padding = windowSize.pagePadding;
        final twoUp = !windowSize.isCompact;

        // One sampled backdrop for the whole screen instead of one per glass
        // card.
        return BackdropGroup(
          child: ListView(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 32),
            children: [
              RevealOnEntrance(
                child: twoUp
                    ? const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: WelcomeHeader()),
                          SizedBox(width: _gap),
                          SizedBox(width: 280, child: MusicWidget()),
                        ],
                      )
                    : const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WelcomeHeader(),
                          SizedBox(height: _gap),
                          MusicWidget(),
                        ],
                      ),
              ),
              const SizedBox(height: _gap),
              const RevealOnEntrance(
                delay: Duration(milliseconds: 60),
                child: HomeSearchBar(),
              ),
              const SizedBox(height: 28),
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
          ),
        );
      },
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
