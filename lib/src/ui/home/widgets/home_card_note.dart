import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// The neutral line a dashboard card shows in place of rows it has none of.
///
/// One centred line and nothing else. The glyph plate it used to carry above
/// the message was the loudest thing in an otherwise empty card, which put the
/// most emphasis on the cards with the least in them.
///
/// [icon] survives for the error notes, where the glyph is the signal that
/// something went wrong rather than decoration on an ordinary empty state.
class HomeCardNote extends StatelessWidget {
  const HomeCardNote({
    super.key,
    this.icon,
    required this.message,
    this.padding = const EdgeInsets.symmetric(vertical: 22),
  });

  final IconData? icon;
  final String message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Spans the card on purpose: the parent column is start-aligned, so a
    // shrink-wrapped note would sit against the left edge and `textAlign`
    // would have nothing to centre within.
    return Container(
      width: double.infinity,
      padding: padding,
      child: Column(
        children: [
          if (icon != null) ...[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.glassFill,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: palette.accent),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.typography.ui(
              size: 13.5,
              color: palette.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a bento card fades to with nothing hovering it.
///
/// Layer opacity, so a resting card's title and contents recede along with its
/// surface. This is the one number that decides how faint the dashboard reads
/// before a pointer finds it.
const double _idleOpacity = 0.4;

/// The bento card frame: a title row with an optional trailing action over
/// the card's own content.
///
/// All four dashboard cards — Tasks, Reminders, Study time, Nutrition —
/// share this shell rather than each drawing its own `GlassCard` and header,
/// so the title's type scale, the pencil's placement and the gap above the
/// content stay in one place instead of four copies that can drift apart.
class HomeCardFrame extends StatelessWidget {
  const HomeCardFrame({
    super.key,
    required this.title,
    required this.child,
    this.onEdit,
    this.actionIcon = PhLight.pencilSimple,
    this.actionTooltip = 'Edit',
    this.onTap,
    this.hoverLift,
    this.semanticLabel,
  });

  final String title;
  final Widget child;

  /// When set, [actionIcon] appears at the row's trailing edge. Omit it for a
  /// card with nothing to edit rather than wiring it to a no-op.
  final VoidCallback? onEdit;

  /// The glyph [onEdit] wears. A pencil by default, because most cards edit
  /// something that already exists; Study time and Nutrition pass a plus,
  /// because theirs adds a new entry instead.
  final IconData actionIcon;

  /// Announced and tooltipped for [onEdit]. Must agree with [actionIcon] — a
  /// plus labelled "Edit" reads as a bug to anyone using a screen reader.
  final String actionTooltip;

  final VoidCallback? onTap;

  /// Passed through to the underlying [GlassCard], defaulting on. Every card
  /// in the bento dims at rest and lights under a pointer whether or not it is
  /// tappable — Tasks, whose content is interactive row by row, carries no
  /// [onTap] of its own and still lights. Pass false for a card that should
  /// not react to one at all.
  final bool? hoverLift;

  /// Passed straight through to the underlying [GlassCard]: announced in
  /// place of the card's contents when the whole card is one control. Only
  /// meaningful alongside [onTap].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final glass = context.useLiquidGlass;

    return GlassCard(
      // A phone-scale corner on glass. 14 is tuned to a dense desktop bento;
      // at arm's length on a 393pt screen it reads as a hard edge.
      radius: glass ? 22 : 14,
      glass: glass,
      onTap: onTap,
      hoverLift: hoverLift ?? true,
      // Null on glass: this fades a card until a pointer lights it, and a
      // touch device never produces one, so every card would sit at 0.4 for
      // the life of the screen.
      idleOpacity: glass ? null : _idleOpacity,
      semanticLabel: semanticLabel,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: context.typography.display(
                    size: 20,
                    weight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (onEdit != null)
                Tooltip(
                  message: actionTooltip,
                  child: InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: Icon(actionIcon,
                          size: 17, color: palette.textMuted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
