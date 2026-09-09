import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/milo_providers.dart';
import '../home/widgets/milo_orb.dart';
import '../milo/widgets/session_drawer.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// Milo's home in the sidebar: history on the left, Chat on the right, the
/// orb below, and the last thing Milo said under that.
///
/// Collapsed, everything but the orb goes — the orb is the one control that
/// still reads at 72pt, and tapping it opens the panel either way.
class MiloDock extends ConsumerWidget {
  const MiloDock({super.key, required this.showLabels});

  final bool showLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    if (!showLabels) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: MiloOrb(diameter: 48),
      );
    }

    final lastLine = ref.watch(
      miloConversationProvider.select(
        (state) => state.messages.isEmpty ? null : state.messages.last.text,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message: 'Chat history',
                child: InkWell(
                  onTap: () => showSessionDrawer(context),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(PhLight.clockCounterClockwise,
                        size: 17, color: palette.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Milo',
                  style: context.typography.display(
                    size: 17,
                    weight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              InkWell(
                onTap: () => Scaffold.of(context).openEndDrawer(),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text(
                    'Chat >',
                    style: context.typography.ui(
                      size: 12.5,
                      weight: FontWeight.w600,
                      // `accentBright`, not `accent`: at 12.5pt this is a
                      // link, and #7005BB does not read on this ground at
                      // that size. `accent` is reserved for the nav
                      // selection, which is larger and underlined besides.
                      color: palette.accentBright,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Center(child: MiloOrb(diameter: 128)),
          const SizedBox(height: 12),
          if (lastLine != null && lastLine.isNotEmpty)
            Text(
              lastLine,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: context.typography.ui(
                size: 13,
                height: 1.35,
                color: palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
