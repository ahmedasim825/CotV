import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

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
