import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// How much of the sidebar is showing.
enum SidebarMode {
  /// Icons and labels.
  expanded,

  /// Icons only.
  ///
  /// No longer reachable from the UI: the one remaining control toggles
  /// [hidden] against [expanded]. The mode is kept because it still renders —
  /// `MiloDock` has a compact layout keyed off [showsLabels], and tests build
  /// a collapsed rail directly — so restoring a trigger is all it would take.
  collapsed,

  /// Nothing — the content pane takes the full window, and the collapse
  /// control in `WindowChrome` brings it back.
  hidden;

  double get width {
    switch (this) {
      case SidebarMode.expanded:
        return 188;
      case SidebarMode.collapsed:
        return 72;
      case SidebarMode.hidden:
        return 0;
    }
  }

  bool get showsLabels => this == SidebarMode.expanded;
}

/// The left rail: five destinations, the Milo dock and a settings gear.
///
/// It used to open with its own row of width controls. Opening and closing the
/// rail now belongs to `WindowChrome`, beside the window buttons, so the rail
/// starts straight at its first destination.
///
/// The dock is passed in rather than built here so this file stays layout and
/// the dock keeps its own provider watches.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.mode,
    required this.destination,
    required this.onSelect,
    this.dock,
  });

  final SidebarMode mode;
  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  /// The Milo section. Null until Task 4 supplies it.
  final Widget? dock;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final glass = context.useLiquidGlass;

    final Widget rail = AnimatedContainer(
      duration: context.motion.fast,
      curve: AppMotion.spring,
      width: mode.width,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.hairline)),
        // One flat fill on every platform. This used to be transparent off
        // iOS — the rail was an edge rather than a surface — and a top-weighted
        // specular gradient on glass; the redesign replaced both with a single
        // value, so the rail reads the same whatever is behind it.
        color: kRailFill,
      ),
      // Below the collapsed width the row contents overflow mid-animation;
      // clipping is cheaper than rebuilding each row against the live width.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: mode.width,
          maxWidth: mode.width == 0 ? SidebarMode.collapsed.width : mode.width,
          // Scroll, but only once the content genuinely does not fit.
          //
          // Almost everything in this column is a fixed height — five nav
          // rows, the dock's 205pt orb box, the footer gear — and [Spacer]
          // is the only thing absorbing slack. Below roughly 620pt of
          // height there is no slack left and the column overflows, which
          // is what the yellow-and-black stripe on a short window was.
          //
          // The 205pt term is the docked rail's alone: iOS passes no [dock],
          // showing Milo in the Home pane instead, so the column is that much
          // shorter there and reaches this ceiling much later. The workaround
          // still has to stand, because Windows still docks.
          //
          // A plain [SingleChildScrollView] would fix the overflow and
          // break the layout: [Spacer] needs a bounded height, and inside
          // an unbounded scrollable it has none, so the gear would ride up
          // under the dock instead of sitting at the bottom. The
          // min-height + [IntrinsicHeight] pairing gives the column the
          // viewport's height to divide when there is room, and lets it
          // grow past that — scrolling — when there is not.
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.hasBoundedHeight
                        ? constraints.maxHeight
                        : 0.0,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      // Just the floor for a short window. How far down the
                      // nav actually sits is settled by the two [Spacer]s
                      // below, not here.
                      //
                      // No bottom inset: Milo's ground has to reach the
                      // window's bottom edge, so that one moves inside it.
                      padding: const EdgeInsets.only(top: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Slack above the nav as well as below it, split 2:5,
                          // so the block floats down as the window grows
                          // instead of staying pinned under the title bar.
                          // A top inset scaled off the height was the first
                          // attempt and reacted to the wrong thing: what
                          // decides how much room there is to give is the slack
                          // left after the rows and Milo's block, not the
                          // height itself. On a short window both collapse to
                          // zero and the scroll workaround above takes over.
                          const Spacer(flex: 2),
                          for (final item in AppDestinationX.navItems)
                            SidebarNavItem(
                              destination: item,
                              isSelected: item == destination,
                              showLabel: mode.showsLabels,
                              onTap: () => onSelect(item),
                            ),
                          const Spacer(flex: 5),
                          // Milo's section, and everything below it. The fill
                          // runs behind the dock, the gear and the bottom
                          // inset both, so the section reads as a band across
                          // the foot of the rail rather than a panel floating
                          // above one.
                          DecoratedBox(
                            decoration: const BoxDecoration(
                              color: _miloSectionFill,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (dock != null) ...[
                                  const SizedBox(height: 14),
                                  dock!,
                                ],
                                const SizedBox(height: 10),
                                _FooterGear(
                                  isSelected:
                                      destination == AppDestination.settings,
                                  onTap: () =>
                                      onSelect(AppDestination.settings),
                                ),
                                SizedBox(
                                  height:
                                      18 + MediaQuery.paddingOf(context).bottom,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    if (!glass) return rail;

    // A fixed surface, which is the one place [GlassShell]'s doc says a
    // backdrop blur belongs — it is not inside a scrollable, so the filter
    // re-reads a backdrop that only changes when the pane behind it scrolls.
    //
    // Clipped to the rail's own width; an unclipped BackdropFilter blurs the
    // whole screen, which here would mean blurring the pane it sits beside.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _railBlurSigma,
          sigmaY: _railBlurSigma,
        ),
        child: rail,
      ),
    );
  }
}

/// How far the iOS rail blurs the pane behind it.
///
/// Higher than a card's 24: the rail is a permanent piece of chrome standing
/// against scrolling content, and the content edge has to dissolve rather than
/// stay legible through it.
const double _railBlurSigma = 30;

/// One destination row.
///
/// Selection reads three ways at once: the glyph and the label go white, a
/// rounded box is stroked around the row with a gradient that has faded out
/// well before its top-right corner, and a nub glows against the rail's left
/// edge. The box carries an inset shadow but no fill, so the rail reads
/// through it.
///
/// The box is an [_ActiveTabPainter], because [BoxDecoration] can express
/// neither a gradient border nor an inset shadow. The nub is a plain
/// [DecoratedBox] — its shadow is an ordinary drop shadow, which [BoxShadow]
/// does handle.
///
/// Selection cross-fades rather than cutting: `t` below runs 0 to 1 over
/// [AppMotionScale.hover], and everything that changes reads off it, so the
/// old row's box fades out as the new one's fades in. Under reduced motion
/// that duration is zero and the cut comes back.
class SidebarNavItem extends StatelessWidget {
  const SidebarNavItem({
    super.key,
    required this.destination,
    required this.isSelected,
    required this.showLabel,
    required this.onTap,
  });

  final AppDestination destination;
  final bool isSelected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return TweenAnimationBuilder<double>(
      // No `begin`, deliberately: the tween picks up from wherever the last
      // one left off, so a tab switched mid-fade carries on from what is on
      // screen instead of snapping back to 0.
      tween: Tween<double>(end: isSelected ? 1 : 0),
      duration: context.motion.hover,
      curve: Curves.easeOut,
      builder: (context, t, _) => _build(context, palette, t),
    );
  }

  Widget _build(BuildContext context, AppPalette palette, double t) {
    // White at rest when selected, not the accent: the violet moved out to the
    // box's stroke and the edge nub, and #7005BB text inside a violet-lit box
    // read as muddy — it measures 1.80:1 against this ground, under even the
    // 3:1 bar large text gets.
    final color = Color.lerp(palette.textMuted, palette.textPrimary, t)!;

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      child: Tooltip(
        message: showLabel ? '' : destination.label,
        child: InkWell(
          onTap: onTap,
          // The theme's fallback hover and press washes are a full-bleed
          // accent rectangle here, because this InkWell sets no
          // `borderRadius` — which fought the selected row's rounded box and
          // spilled past it. The row's own colours are the whole feedback now.
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Stack(
            children: [
              // First, so it paints *under* the box: its glow is wide, and
              // over the top it washed the box's interior and read as an
              // over-strong inset shadow. Outside the row's horizontal padding
              // either way — the nub is flush with the rail's own left edge,
              // not with the content.
              if (t > 0)
                Positioned.fill(
                  left: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Opacity(
                      opacity: t,
                      child: const _ActiveTabNub(
                        key: ValueKey('sidebar-active-tab'),
                      ),
                    ),
                  ),
                ),
              Padding(
                // Asymmetric, not the 16 this carried on both sides: the box
                // stops short of the rail's edges on both sides, and the left
                // also has to clear the 6pt nub.
                padding: const EdgeInsets.only(
                  left: 14,
                  right: 20,
                  top: 1,
                  bottom: 1,
                ),
                child: CustomPaint(
                  // Paints behind its child, so the stroke and the inset
                  // shadow sit under the glyph and the label.
                  painter: t > 0 ? _ActiveTabPainter(t) : null,
                  child: SizedBox(
                    height: minTouchTarget,
                    child: Padding(
                      // Inside the box, so the glyph clears the stroke and the
                      // glow along it rather than sitting against them.
                      padding: const EdgeInsets.only(left: 14),
                      child: Row(
                        children: [
                          Icon(destination.icon, size: 19, color: color),
                          if (showLabel) ...[
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                destination.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.typography.ui(
                                  size: 16,
                                  weight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glowing marker against the rail's left edge.
///
/// Rounded on its right side only, so it reads as something pushed in from off
/// screen rather than a floating pill.
class _ActiveTabNub extends StatelessWidget {
  const _ActiveTabNub({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _nubWidth,
      height: _nubHeight,
      decoration: const BoxDecoration(
        color: _activeGlow,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(_activeRadius),
          bottomRight: Radius.circular(_activeRadius),
        ),
        boxShadow: [
          // blur 30 / spread 4 in the mock, over that same 1.5x canvas.
          BoxShadow(
            color: _activeGlow,
            blurRadius: 30 / 1.5,
            spreadRadius: 4 / 1.5,
          ),
        ],
      ),
    );
  }
}

/// The rounded box around the selected row: a gradient stroke and an inset
/// shadow, over no fill, the whole thing at [_activeOpacity].
///
/// Both have to be painted. [BoxDecoration.border] takes a flat colour, not a
/// gradient, and [BoxShadow] is always an outer shadow.
///
/// The layer opacity is the thing that makes this subtle — not the individual
/// alphas, which are all full strength. Getting that backwards means reaching
/// for a fudge factor on each of them separately and never quite matching.
///
/// [t] is the selection cross-fade, 0 to 1.
class _ActiveTabPainter extends CustomPainter {
  const _ActiveTabPainter(this.t);

  /// How far through the selection fade this row is.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Rect bounds = Offset.zero & size;
    final RRect box = RRect.fromRectAndRadius(
      bounds,
      const Radius.circular(_activeRadius),
    );

    // Everything below goes into one layer, composited at 20%. No fill — the
    // rail reads straight through the middle of the row.
    canvas.saveLayer(
      bounds,
      Paint()..color = Color.fromRGBO(0, 0, 0, _activeOpacity * t),
    );

    // The inset shadow: the inverse of the shape — colour everywhere the
    // shape, shifted and blurred, does *not* reach. Fill the box, then punch
    // the shifted copy back out with `dstOut`. With the offset pushing right,
    // what survives is a band down the left edge.
    canvas.save();
    canvas.clipRRect(box);
    canvas.saveLayer(bounds, Paint());
    canvas.drawRRect(box, Paint()..color = _activeGlow);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        // A negative spread pulls the casting edge back out of the shape, so
        // less of the interior falls in shadow.
        bounds.inflate(-_shadowSpread).shift(const Offset(_shadowDx, 0)),
        const Radius.circular(_activeRadius),
      ),
      Paint()
        ..blendMode = BlendMode.dstOut
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _shadowSigma),
    );
    canvas.restore();
    canvas.restore();

    // The stroke sits inside the bounds rather than centred on them, so the
    // box is exactly `size` wide however thick the stroke gets.
    canvas.drawRRect(
      box.deflate(_activeStroke / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _activeStroke
        ..shader = const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [_activeStrokeLit, Color(0x00000000)],
        ).createShader(bounds),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ActiveTabPainter oldDelegate) => oldDelegate.t != t;
}

/// The rail's own fill: white at 5%, in a layer at 50% opacity.
///
/// Public because the rail does not paint all of itself: the strip behind the
/// window chrome is drawn by `AppShell`, which has to match this exactly or the
/// seam shows at the title bar.
const Color kRailFill = Color(0x06FFFFFF);

/// Milo's section: #D9D9D9 at 100% fill in a layer at 7% opacity.
///
/// Painted here rather than inside `MiloDock`, because the section's ground
/// runs to the bottom edge of the window — past the dock's own content, behind
/// the settings gear and through the rail's bottom inset. The dock does not
/// know where that edge is, and in the iOS Home pane there is no such edge.
const Color _miloSectionFill = Color(0x12D9D9D9);

/// Corner radius shared by the active row's box and its edge nub.
const double _activeRadius = 10;

/// Width of the active row's gradient stroke.
const double _activeStroke = 1.5;

/// The lit end of that stroke, at the box's bottom-left corner.
const Color _activeStrokeLit = Color(0xFFC084FC);

/// What the whole box is composited at.
///
/// The stroke and the inset shadow are both drawn at full strength and then
/// taken down together by this, which is what the design does. Dimming them
/// individually instead gets close but never lands, because their relative
/// weights drift apart.
const double _activeOpacity = 0.15;

/// The light the active row is lit by: the nub's fill, the nub's glow and the
/// inset shadow inside the box are all this one colour.
///
/// Note the digits — #A92DDF, not #A29DDF. The transposition turns a saturated
/// purple into a pale periwinkle that reads as plain white against this ground,
/// which is exactly what it looked like when it was wrong.
const Color _activeGlow = Color(0xFFA92DDF);

/// The nub, at 9x49 in the mock over a 1.5x canvas.
const double _nubWidth = 6;
const double _nubHeight = 33;

/// The inset shadow, at x=12 / blur=16 / spread=-2 in the mock, over that same
/// 1.5x canvas. Blur there is a CSS-style radius; a mask filter wants a sigma,
/// which is about half of it.
const double _shadowDx = 12 / 1.5;
const double _shadowSigma = 16 / 1.5 / 2;
const double _shadowSpread = -2 / 1.5;

class _FooterGear extends StatelessWidget {
  const _FooterGear({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: 'Settings',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: minTouchTarget,
              height: minTouchTarget,
              child: Icon(
                PhLight.gear,
                size: 20,
                color: isSelected ? palette.accent : palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
