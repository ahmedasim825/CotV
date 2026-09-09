import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The translucent glass surface the dashboard is built from.
///
/// Where [CustomCard] is an opaque plate, this one is a sheet of glass: the
/// canvas and its ambient glow orbs are blurred and tinted through it,
/// a specular wash runs down from the top edge as if light were refracting
/// through it, and a pointer lifts it off the page.
///
/// The API deliberately mirrors [CustomCard] so a card can be moved between
/// the two by changing the constructor name and nothing else.
///
/// **Cost.** A [BackdropFilter] samples everything painted behind it, once
/// per frame it is on screen, and this card is used inside a scrolling list
/// — which is exactly the pattern `GlassShell.blurBackground` warns against.
/// Three things keep that affordable: the filter is a `BackdropFilter.grouped`
/// so a screenful of them shares one sampled backdrop rather than taking one
/// each, every card is its own repaint boundary, and the whole effect sits
/// behind [blurEnabled] so it can be measured against a build without it.
/// A screen using more than one of these should wrap its scroll view in a
/// [BackdropGroup] for the sharing to actually happen.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 20,
    this.accent,
    this.tint,
    this.onTap,
    this.selected = false,
    this.elevated = true,
    this.blur,
    this.hoverLift,
    this.semanticLabel,
  });

  /// The app-wide backdrop-blur switch.
  ///
  /// Flip this to false to drop every [BackdropFilter] in one edit — the
  /// cards keep their geometry, border, specular and shadow, and composite
  /// their fill over the surface instead of sampling through it. Worth
  /// measuring against on a mid-range phone before deciding the blur pays
  /// for its frames.
  static const bool blurEnabled = true;

  /// Blur radius, in both axes.
  static const double blurSigma = 16;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// When set, the card borrows this color for its border, its hover glow
  /// and (when [selected]) its fill. Defaults to the theme accent.
  final Color? accent;

  /// Overrides the fill entirely. Takes precedence over [accent].
  final Color? tint;

  final VoidCallback? onTap;

  /// Draws the card in its active state: accent border at full strength
  /// over an accent-washed fill.
  final bool selected;

  final bool elevated;

  /// Overrides [blurEnabled] for this card alone.
  final bool? blur;

  /// Whether a pointer hovering the card lifts and lights it.
  ///
  /// Defaults to whether the card is tappable, because that is what the
  /// lift promises. Pass true to light up a card whose contents are
  /// interactive even though the card itself is not.
  final bool? hoverLift;

  /// Announced in place of the card's contents when the whole card is one
  /// control. Only meaningful alongside [onTap].
  final String? semanticLabel;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _pressed = false;
  bool _hovered = false;

  bool get _interactive => widget.onTap != null;

  bool get _lifts => widget.hoverLift ?? _interactive;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (!_lifts) return;
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.accent ?? palette.accent;
    final motion = context.motion;
    final radius = BorderRadius.circular(widget.radius);
    final blurred = widget.blur ?? GlassCard.blurEnabled;

    final Color glass;
    if (widget.tint != null) {
      glass = widget.tint!;
    } else if (widget.selected) {
      glass = Color.alphaBlend(
        accent.withValues(alpha: 0.12),
        palette.glassSurface,
      );
    } else {
      glass = palette.glassSurface;
    }

    // Without a blur behind it the fill would be genuinely see-through, and
    // the ambient glow orbs would read straight through the card. Compositing
    // it over the surface keeps the same colour with none of the cost.
    final fill = blurred ? glass : Color.alphaBlend(glass, palette.surface);

    final Color borderColor;
    if (widget.selected) {
      borderColor = accent;
    } else if (widget.accent != null) {
      borderColor = accent.withValues(alpha: 0.35);
    } else {
      borderColor = palette.glassBorder;
    }

    // The specular is folded into the fill rather than laid over the card:
    // a translucent white wash on top of the content would lighten the text
    // under it, which on Pearl is the difference between readable and not.
    Widget plate = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: borderColor, width: widget.selected ? 1.5 : 1),
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

    if (blurred) {
      plate = ClipRRect(
        borderRadius: radius,
        // `.grouped` rather than the plain constructor: it shares one
        // sampled backdrop with every other grouped filter under the same
        // `BackdropGroup`, which is what makes a column of glass cards cost
        // roughly one blur instead of one each. With no group above it, it
        // resolves a null key and behaves exactly like a plain filter, so
        // the card is safe to use anywhere.
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(
            sigmaX: GlassCard.blurSigma,
            sigmaY: GlassCard.blurSigma,
          ),
          child: plate,
        ),
      );
    }

    // Both shadows sit outside the clip, where a shadow has to be to be
    // visible at all. The drop shadow gives the card its height off the
    // page; the accent glow is the hover state, and is negative-spread so
    // it reads as light coming off the card rather than as a second border.
    final lifted = AnimatedContainer(
      duration: motion.hover,
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
              color: accent.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: -2,
            ),
        ],
      ),
      child: plate,
    );

    final card = RepaintBoundary(
      child: MouseRegion(
        cursor: _interactive
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: lifted,
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
          duration: motion.fast,
          curve: AppMotion.spring,
          child: card,
        ),
      ),
    );
  }
}
