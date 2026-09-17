import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A day's heading over a card of rows.
///
/// Deliberately not a [GlassCard]: that widget brings a press scale, a hover
/// lift, an inner-glow painter and a 2%/8% fill ladder, none of which this
/// plate wants. The card here is a grouping device — it only has to say where
/// the day starts and stops — so it is a plain decoration at 3% over a 6% rim.
///
/// [Border.all] is an *inside* stroke in Flutter, which is what the design
/// means by a 1px rim drawn inside the shape.
class BentoSection extends StatelessWidget {
  const BentoSection({
    super.key,
    required this.title,
    required this.rows,
    this.footer,
    this.isPast = false,
  });

  final String title;

  /// The rows, already built. Separated here rather than by the caller so
  /// every section rules its rows identically.
  final List<Widget> rows;

  /// Pinned under the last row, below a rule of its own. The inline add
  /// control on the Today section, and nothing anywhere else.
  final Widget? footer;

  /// Dims the whole section — heading and card together — to 60%.
  final bool isPast;

  static const double _radius = 16;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(_rule(palette));
      children.add(rows[i]);
    }
    if (footer != null) {
      if (children.isNotEmpty) children.add(_rule(palette));
      children.add(footer!);
    }

    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.typography.display(
            size: 28,
            weight: FontWeight.w700,
            letterSpacing: -0.8,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        if (children.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.bentoFill,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: palette.bentoBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
      ],
    );

    // An `Opacity` rather than dimming each colour: 60% on a section means
    // the section composited at 60%, which is what fades the checked purple
    // box in a past day's card as well as its text. It is one save layer over
    // static content, and nothing inside pushes a backdrop filter — the nav
    // bar's is a sibling in the Scaffold, not an ancestor of this.
    return isPast ? Opacity(opacity: 0.6, child: section) : section;
  }

  Widget _rule(AppPalette palette) => Divider(
        height: 1,
        thickness: 1,
        color: palette.bentoBorder,
      );
}
