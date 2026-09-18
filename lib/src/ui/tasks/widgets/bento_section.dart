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
///
/// ## Who pads what
///
/// The card pads itself vertically and **not** horizontally; each row pads its
/// own sides. That split exists so a row can be swiped: a delete panel sliding
/// out behind one has to reach the card's inner edge, and it cannot if the
/// card holds the inset. The rules and the footer are padded here instead,
/// since neither is ever swiped, which is what keeps their inset identical to
/// what it was when the card owned it.
class BentoSection extends StatelessWidget {
  const BentoSection({
    super.key,
    required this.title,
    required this.rows,
    this.footer,
    this.trailing,
    this.isPast = false,
  });

  final String title;

  /// The rows, already built. Separated here rather than by the caller so
  /// every section rules its rows identically.
  final List<Widget> rows;

  /// Pinned under the last row, below a rule of its own. The inline add
  /// control on the Today section, and nothing anywhere else.
  final Widget? footer;

  /// Sits at the right of the heading, on its baseline.
  ///
  /// The screen's filter menu, and only on the first section — the design puts
  /// it level with the first heading rather than in a bar of its own, so which
  /// section carries it depends on which one comes first. Under the Past
  /// filter that is Yesterday.
  final Widget? trailing;

  /// Dims the whole section — heading and card together — to 60%.
  final bool isPast;

  static const double _radius = 16;

  /// The inset rows, rules and the footer share. Applied per-child rather than
  /// to the card — see the class doc.
  static const EdgeInsets _inset = EdgeInsets.only(left: 12, right: 14);

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
      children.add(Padding(padding: _inset, child: footer!));
    }

    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: context.typography.display(
                  size: 28,
                  weight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: palette.textPrimary,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 14),
        if (children.isNotEmpty)
          // Clipped so a swiped row's delete panel is cut by the card's own
          // corners instead of squaring them off. `Clip.antiAlias` is the
          // default and pushes no save layer, which is what keeps the note on
          // [isPast] below true.
          ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.bentoFill,
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: palette.bentoBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
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

  Widget _rule(AppPalette palette) => Padding(
    padding: _inset,
    child: Divider(height: 1, thickness: 1, color: palette.bentoBorder),
  );
}
