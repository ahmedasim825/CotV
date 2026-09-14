import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The blur on the hover glow, which sits inside the card's own edge.
const double _hoverGlowBlur = 4;

/// How far the [GlassCard.glass] variant blurs what is behind it.
///
/// Below [GlassShell]'s 28, which is tuned for a fixed hero surface. A card
/// sits over the orb field, which is already soft, and over-blurring it
/// flattens the orbs into a single wash — the thing the card is meant to show.
const double _glassBlurSigma = 24;

/// The panel the dashboard is built from.
///
/// Where [CustomCard] is an opaque plate, this is barely a surface at all — a
/// white-at-2% fill behind a hairline rim, with the ambient background and its
/// glow orbs reading straight through. What makes it a card is what happens
/// under a pointer, not what it is at rest.
///
/// **The hover state carries the design.** A card given an [idleOpacity] rests
/// at that opacity — fill, rim, title, rows and numbers alike — and comes to
/// full strength when hovered, gaining an accent rim and an accent glow just
/// inside it. At rest it has no rim at all. The fill itself never changes, and
/// the card does not resize: the three that do change animate together on
/// `context.motion.hover`, so they stop together under reduced motion.
///
/// This was frosted glass on every platform until the homepage restyle, which
/// stripped the blur because Windows could not afford it. [glass] is that
/// material brought back, now that only iOS asks for it — see its own doc
/// below, and note the home `ListView` wraps itself in a `BackdropGroup` again
/// on that path. Off [glass], the card is the flat plate described above, and
/// the ambient glow orbs are most of what it shows.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 20,
    this.accent,
    this.rim,
    this.tint,
    this.onTap,
    this.selected = false,
    this.hoverLift,
    this.idleOpacity,
    this.glass = false,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// When set, the card borrows this color for its hover rim and glow, and
  /// (when [selected]) for its fill. Defaults to the theme accent.
  final Color? accent;

  /// Overrides the colour of the rim at rest. A hovered card takes the accent
  /// whatever this is set to.
  final Color? rim;

  /// Overrides the fill entirely. Takes precedence over [accent].
  final Color? tint;

  final VoidCallback? onTap;

  /// Draws the card in its active state: accent rim at full strength over an
  /// accent-washed fill.
  final bool selected;

  /// Whether a pointer over the card lights it.
  ///
  /// Defaults on for a card that dims or is tappable, since both of those
  /// promise a lit state. Pass false for a card that should never react.
  final bool? hoverLift;

  /// The opacity the card rests at with nothing hovering it, or null for a
  /// card that never dims.
  ///
  /// Layer opacity, not a fill alpha: the contents fade with the surface,
  /// which is the point — an unhovered card is meant to recede.
  final double? idleOpacity;

  /// Draws the card as real glass: a [BackdropFilter] over whatever is behind
  /// it, under a brighter fill, a specular wash and a lit top bevel — the
  /// numbers taken from [GlassShell] rather than invented, so the two
  /// materials cannot drift apart.
  ///
  /// **A flag rather than a separate widget**, so there is one card with one
  /// hover, press, semantics and glow implementation. And **a flag rather than
  /// a platform check**, so this widget never asks where it is running:
  /// `context.useLiquidGlass` is read by the handful of composition sites that
  /// decide, and nothing below them.
  ///
  /// Set this and you inherit one hard constraint: **no ancestor of this card
  /// may push a save layer**, or the filter samples that buffer instead of the
  /// page and the card blurs nothing. [Opacity] is the usual culprit —
  /// `RenderOpacity.alwaysNeedsCompositing` is true at every non-zero alpha,
  /// 1.0 included — which is why `RevealOnEntrance` stands down on the glass
  /// path rather than wrapping each section in one.
  ///
  /// [idleOpacity] is not part of that constraint: the blur goes on outside
  /// it, so it is a descendant and samples nothing. It should still be null
  /// here, for an unrelated reason — it fades a card until a pointer lights
  /// it, and a touch device has no pointer to light it with.
  final bool glass;

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

  bool get _lights =>
      widget.hoverLift ?? (widget.idleOpacity != null || _interactive);

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (!_lights) return;
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.accent ?? palette.accent;
    final motion = context.motion;
    final radius = BorderRadius.circular(widget.radius);

    // Glass rests on `glassFill`, four times the flat card's 2%: over a blur,
    // 2% white is indistinguishable from no fill at all.
    final Color base = widget.glass ? palette.glassFill : palette.cardFill;

    final Color fill;
    if (widget.tint != null) {
      fill = widget.tint!;
    } else if (widget.selected) {
      fill = Color.alphaBlend(accent.withValues(alpha: 0.12), base);
    } else {
      fill = base;
    }

    final Color rimColor;
    if (_hovered || widget.selected) {
      rimColor = accent;
    } else if (widget.rim != null) {
      rimColor = widget.rim!;
    } else if (widget.glass) {
      // Glass keeps a rim at rest, where the flat card has none: the edge is
      // what separates one pane of glass from the blurred page under it.
      rimColor = palette.hairline;
    } else {
      // Nothing at rest. The card is read as its contents and the ground
      // showing through them; the rim is the hover state's to introduce.
      rimColor = Colors.transparent;
    }

    Widget card = AnimatedContainer(
      duration: motion.hover,
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        // A gradient rather than a flat colour on glass — the specular wash
        // down the top 45%, lifted verbatim from [GlassShell]. BoxDecoration
        // takes one or the other, so the flat path keeps `color`.
        color: widget.glass ? null : fill,
        gradient: widget.glass
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(palette.glassSpecular, fill),
                  fill,
                ],
                stops: const [0.0, 0.45],
              )
            : null,
        border: Border.all(color: rimColor, width: widget.selected ? 1.5 : 1),
      ),
      // The bevel: a single lit edge along the top, so the pane reads as
      // having a thickness that catches light. Foreground, so it lands over
      // the fill rather than under it.
      foregroundDecoration: widget.glass
          ? BoxDecoration(
              borderRadius: radius,
              border: Border(
                top: BorderSide(color: palette.innerHighlight),
              ),
            )
          : null,
      child: widget.child,
    );

    final idle = widget.idleOpacity;
    if (idle != null) {
      card = AnimatedOpacity(
        opacity: _hovered ? 1 : idle,
        duration: motion.hover,
        curve: Curves.easeOut,
        child: card,
      );
    }

    // Outside the opacity, so the glow lights at full strength rather than
    // being multiplied by whatever the card is currently faded to. A
    // foreground painter, because an inner glow has to land over the fill
    // rather than behind it.
    card = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _hovered ? 1 : 0),
      duration: motion.hover,
      curve: Curves.easeOut,
      builder: (context, lit, child) => CustomPaint(
        foregroundPainter: lit == 0
            ? null
            : _InnerGlow(color: accent, radius: widget.radius, lit: lit),
        child: child,
      ),
      child: card,
    );

    card = RepaintBoundary(
      child: MouseRegion(
        cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: card,
      ),
    );

    if (widget.glass) {
      // Outermost, and that is the whole trick: a BackdropFilter samples what
      // has already been painted beneath it, so anything between it and the
      // page that pushes a save layer gets sampled instead of the page. The
      // RepaintBoundary just above is safe — it pushes an offset layer, not a
      // save layer, and keeping the filter outside it lets the card's contents
      // stay raster-cached while the filter re-reads the backdrop each frame.
      //
      // The clip is not optional: an unclipped BackdropFilter blurs the entire
      // screen rather than its own bounds.
      //
      // `.grouped` so sibling cards share one backdrop capture per frame when
      // a `BackdropGroup` is above them. With no group in scope it degrades to
      // an ordinary filter, so a card pumped alone in a test still renders.
      card = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(
            sigmaX: _glassBlurSigma,
            sigmaY: _glassBlurSigma,
          ),
          child: card,
        ),
      );
    }

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

/// The hover glow: accent light laid just inside the card's own edge.
///
/// **Not a [BoxShadow].** A box shadow is a blurred silhouette of the whole
/// card painted behind it, which reads as a halo only because a card is
/// normally opaque enough to hide the part sitting underneath it. This card is
/// a 2%-white fill, so the silhouette read straight through and the card went
/// solid violet.
///
/// Drawn instead as a blurred stroke along the rim, clipped to the inside of
/// it, which is how an inset shadow is expressed here — [BoxDecoration] has no
/// inset shadow of its own.
class _InnerGlow extends CustomPainter {
  const _InnerGlow({
    required this.color,
    required this.radius,
    required this.lit,
  });

  final Color color;
  final double radius;

  /// 0 unlit through 1 fully lit.
  final double lit;

  @override
  void paint(Canvas canvas, Size size) {
    final rim = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    canvas.save();
    canvas.clipRRect(rim);
    canvas.drawRRect(
      rim,
      Paint()
        ..color = color.withValues(alpha: lit)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _hoverGlowBlur
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _hoverGlowBlur),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerGlow oldDelegate) =>
      oldDelegate.lit != lit ||
      oldDelegate.color != color ||
      oldDelegate.radius != radius;
}
