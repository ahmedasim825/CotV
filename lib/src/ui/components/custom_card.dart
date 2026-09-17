import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's standard content surface: a themed fill, a hairline border, a
/// specular top edge, and hover and press physics when it is tappable.
///
/// This is the single-layer, *opaque* card, and the default for anything
/// that is not a hero. Its two siblings: `GlassShell` carries the nested
/// "double bezel" treatment for hero surfaces, and `GlassCard` is this card
/// rendered in blurred glass, which the dashboard is built from. All three
/// share one radius, border, shadow and motion language.
class CustomCard extends StatefulWidget {
  const CustomCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.accent,
    this.tint,
    this.onTap,
    this.selected = false,
    this.elevated = true,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// When set, the card borrows this color for its border and (when
  /// [selected]) its fill — how the theme picker marks the active theme.
  final Color? accent;

  /// Overrides the fill entirely. Takes precedence over [accent].
  final Color? tint;

  final VoidCallback? onTap;

  /// Draws the card in its active state: accent border at full strength
  /// over an accent-washed fill.
  final bool selected;

  final bool elevated;

  /// Announced in place of the card's contents when the whole card is one
  /// control. Only meaningful alongside [onTap].
  final String? semanticLabel;

  @override
  State<CustomCard> createState() => _CustomCardState();
}

class _CustomCardState extends State<CustomCard> {
  bool _pressed = false;
  bool _hovered = false;

  bool get _interactive => widget.onTap != null;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  /// Only a tappable card lifts: the lift is a promise that something
  /// happens when it is clicked.
  void _setHovered(bool value) {
    if (!_interactive) return;
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.accent;
    final glow = accent ?? palette.accent;

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

    final radius = BorderRadius.circular(widget.radius);

    // The top highlight is folded into the fill as a gradient rather than
    // laid over the card, so it lights the plate without washing out the
    // text sitting on it.
    final plate = AnimatedContainer(
      duration: context.motion.fast,
      curve: AppMotion.spring,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: borderColor,
          width: widget.selected ? 1.5 : 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(palette.glassSpecular, fill), fill],
          stops: const [0.0, 0.45],
        ),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border(top: BorderSide(color: palette.innerHighlight)),
      ),
      child: widget.child,
    );

    // Shadows live out here rather than on the plate: the hover glow is
    // negative-spread light coming off the card, and the lift is a
    // transform, neither of which should animate on the same controller as
    // the fill.
    final card = MouseRegion(
      cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        duration: context.motion.hover,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            if (widget.elevated)
              BoxShadow(
                color: palette.shadow,
                blurRadius: _hovered ? 30 : 22,
                offset: Offset(0, _hovered ? 14 : 10),
              ),
            if (_hovered)
              BoxShadow(
                color: glow.withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: -2,
              ),
          ],
        ),
        child: plate,
      ),
    );

    if (!_interactive) return card;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: context.motion.fast,
          curve: AppMotion.spring,
          child: card,
        ),
      ),
    );
  }
}
