import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/eyebrow_pill.dart';

/// The heading that opens every section: an optional tracked-out eyebrow
/// pill, an editorial title, an optional explanatory line, and an optional
/// trailing control pinned to the title's baseline row.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.accent,
    this.titleSize = 30,
  });

  final String title;

  /// Shown above the title as a pill. Rendered in caps by [EyebrowPill]'s
  /// tracking, so pass it already capitalised for correct screen-reader
  /// pronunciation.
  final String? eyebrow;

  final String? subtitle;

  /// A control that belongs to the section as a whole — a sort toggle, a
  /// filter, an add button.
  final Widget? trailing;

  /// Tints the eyebrow pill. Defaults to the theme accent.
  final Color? accent;

  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          EyebrowPill(label: eyebrow!, color: accent),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: context.typography.display(
                  size: titleSize,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: context.typography.ui(
              size: 13.5,
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
