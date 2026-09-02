import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's standard content surface: a themed fill, a hairline border and
/// an inset top highlight, with optional press physics when it is tappable.
///
/// This is the single-layer card. The nested "double bezel" treatment lives
/// in `GlassShell` and is reserved for hero surfaces; everything else — a
/// habit tile, a journal entry, a settings row — should use this so all of
/// them share one radius, border and shadow language.
class CustomCard extends StatefulWidget {
  const CustomCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.accent,
    this.tint,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dimmed = false,
    this.elevated = true,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// When set, the card borrows this color for its border and (when
  /// [selected]) its fill — how a habit tile carries its own color and how
  /// the theme picker marks the active theme.
  final Color? accent;

  /// Overrides the fill entirely. Takes precedence over [accent].
  final Color? tint;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Draws the card in its active state: accent border at full strength
  /// over an accent-washed fill.
  final bool selected;

  /// Recedes the card without removing it — a completed habit, a past day.
  final bool dimmed;

  final bool elevated;

  /// Announced in place of the card's contents when the whole card is one
  /// control. Only meaningful alongside [onTap].
  final String? semanticLabel;

  @override
  State<CustomCard> createState() => _CustomCardState();
}

class _CustomCardState extends State<CustomCard> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.accent;

    final Color fill;
    if (widget.tint != null) {
      fill = widget.tint!;
    } else if (widget.selected && accent != null) {
      fill = Color.alphaBlend(accent.withValues(alpha: 0.12), palette.surface);
    } else {
      fill = palette.surface;
    }

    final Color borderColor;
    if (widget.selected) {
      borderColor = accent ?? palette.accent;
    } else if (accent != null) {
      borderColor = accent.withValues(alpha: 0.35);
    } else {
      borderColor = palette.hairline;
    }

    final card = AnimatedOpacity(
      opacity: widget.dimmed ? 0.55 : 1,
      duration: AppMotion.fast,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: borderColor,
            width: widget.selected ? 1.5 : 1,
          ),
          boxShadow: widget.elevated
              ? [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border(top: BorderSide(color: palette.innerHighlight)),
        ),
        child: widget.child,
      ),
    );

    if (!_interactive) return card;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: AppMotion.fast,
          curve: AppMotion.spring,
          child: card,
        ),
      ),
    );
  }
}
