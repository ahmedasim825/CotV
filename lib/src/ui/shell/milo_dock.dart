import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/milo_providers.dart';
import '../home/widgets/milo_orb.dart';
import '../milo/widgets/session_drawer.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// Milo's block: history on the left, Chat on the right, the orb below, and
/// the last thing Milo said under that.
///
/// Lives in the sidebar on Windows and in the Home pane on iOS, which is why
/// this is one widget and not two — the arrangement is identical in both, and
/// a copy would leave whichever one the tests did not pump free to drift.
/// Only [padding] differs.
///
/// Collapsed, everything but the orb goes — and a tap on the orb opens the
/// microphone, not the panel: [MiloOrb] wires a plain tap to
/// `miloVoiceProvider.toggle()`, and only a double tap on Windows or a long
/// press on iOS reaches the panel from the orb alone (see [MiloOrbWidget]'s
/// `onTextMilo`). A small Chat glyph rides along beside it at 72pt so the
/// panel stays discoverable by a plain tap even when the sidebar is
/// collapsed. [showLabels] is always true in the Home pane: there is no
/// collapsed Home.
class MiloDock extends ConsumerWidget {
  const MiloDock({
    super.key,
    required this.showLabels,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
  });

  final bool showLabels;

  /// The gutter around the expanded block. The default is tuned to the 188pt
  /// sidebar; the Home pane passes [EdgeInsets.zero], having already applied
  /// its own page padding. Ignored when [showLabels] is false — the collapsed
  /// rail has its own, tighter, inset.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    if (!showLabels) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiloOrb(diameter: 48),
            const SizedBox(height: 6),
            Tooltip(
              message: 'Open Milo chat',
              child: InkWell(
                onTap: () => Scaffold.of(context).openEndDrawer(),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    PhLight.sparkle,
                    size: 15,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final lastLine = ref.watch(
      miloConversationProvider.select(
        (state) => state.messages.isEmpty ? null : state.messages.last.text,
      ),
    );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Stack, not a Row. "Milo" is a section title over the orb below
          // it, so it wants the centre of the rail — and centring it in a
          // Row's leftover space would land it off by half the difference
          // between the 28pt history button and the wider "Chat >" link.
          // Pinning a height centres it vertically too, which the Row could
          // not: `display()` sets height 1.0, so the type box is shorter than
          // either control beside it and the word rode high against them.
          SizedBox(
            height: minTouchTarget,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    message: 'Chat history',
                    child: InkWell(
                      onTap: () => showSessionDrawer(context),
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          // Bold: at 17pt in muted grey the Regular cut read
                          // as too light beside the wordmark next to it.
                          PhBold.clockCounterClockwise,
                          size: 17,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    'Milo',
                    style: context.typography.display(
                      size: 17,
                      weight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => Scaffold.of(context).openEndDrawer(),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
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
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 128 before, briefly 96. The orb reserves 1.6x its diameter for
          // the glow, so this term alone decides most of the block's height:
          // 205pt at 128, 179pt here.
          const Center(child: MiloOrb(diameter: 112)),
          const SizedBox(height: 8),
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
