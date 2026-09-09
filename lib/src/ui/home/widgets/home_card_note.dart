import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// The neutral line a dashboard card shows in place of rows it has none of.
///
/// The full-screen empty states on Tasks and Study can afford a 56pt glyph
/// plate and a two-line sentence; a card that has to sit beside three others
/// cannot. Same language — muted 13.5pt over a `glassFill` circle — at a
/// third of the height.
class HomeCardNote extends StatelessWidget {
  const HomeCardNote({
    super.key,
    required this.icon,
    required this.message,
    this.padding = const EdgeInsets.symmetric(vertical: 22),
  });

  final IconData icon;
  final String message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: padding,
      child: Column(
        children: [
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
    this.onTap,
  });

  final String title;
  final Widget child;

  /// When set, a pencil appears at the row's trailing edge. Omit it for a
  /// card with nothing to edit rather than wiring it to a no-op.
  final VoidCallback? onEdit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return GlassCard(
      radius: 18,
      onTap: onTap,
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
                  message: 'Edit',
                  child: InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: Icon(PhLight.pencilSimple,
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
