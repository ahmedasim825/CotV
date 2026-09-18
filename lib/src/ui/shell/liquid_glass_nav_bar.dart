import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shell.dart';
import '../components/liquid_glass.dart';
import '../theme/app_theme.dart';

/// The floating tab bar: the app's one piece of full Liquid Glass.
///
/// Everything visual comes from [LiquidGlass] — the refraction, the rim
/// specular, the bounded blur, and the fallback when there is no shader to run
/// them. What lives here is the *shape*: how big the capsule is, where it
/// floats, and how it moves.
///
/// ## The footprint never changes, and that is load-bearing
///
/// This widget is handed to `Scaffold.bottomNavigationBar`, and Scaffold
/// measures whatever it gets and republishes that height as the body's
/// `MediaQuery.padding.bottom`. Roughly fifteen places read it — every pane
/// that pads its scroll past the capsule does — and Scaffold publishes it
/// through a `LayoutBuilder`, so a height that changed mid-animation would
/// rebuild every pane's entire subtree *during layout*, once a frame, and
/// force a scroll correction for anything pinned at its maximum extent.
///
/// So the outer box is a fixed [SizedBox] of [expandedHeight] plus the lift,
/// always, and the collapse happens entirely *inside* it, bottom-aligned. The
/// capsule shrinks; the hole it sits in does not.
///
/// For the same reason the shrink animates real width and height rather than a
/// [Transform.scale], which would be cheaper and wrong twice over: it scales
/// the blur with the capsule, and it breaks the size-times-density identity
/// [LiquidGlass] hands its shader to locate its own rect.
class LiquidGlassNavBar extends StatefulWidget {
  const LiquidGlassNavBar({
    super.key,
    required this.destination,
    required this.onSelect,
    required this.collapsed,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  /// Whether the page under the capsule is being scrolled away from.
  ///
  /// A [ValueListenable] rather than a plain bool, so that a direction flip
  /// rebuilds the capsule and nothing else. Routed through `setState` on the
  /// shell it would rebuild the whole pane on every flick.
  final ValueListenable<bool> collapsed;

  /// 71, from the design. Taller than the 56 this started at, which is most
  /// of why the bar now reads as a slab of glass rather than a strip.
  static const double expandedHeight = 71;

  /// Scrolled-away height. Still well past the 44pt minimum, so the capsule
  /// stays usable rather than becoming a decoration you scroll up to reach.
  static const double collapsedHeight = 56;

  /// Inset from the pane's edges. Only reached on a screen too narrow to give
  /// the capsule its full [maxWidth].
  static const double inset = 16;

  /// 354, from the design. On any iPhone this is the capsule's actual width —
  /// 393pt of screen less two 16pt insets leaves 361, so the constraint binds
  /// and the bar measures exactly 354.
  static const double maxWidth = 354;

  /// The hairline [LiquidGlass] draws round itself. Subtracted here so the
  /// row of glyphs sits inside the rim rather than under it.
  static const double rim = 1;

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar>
    with TickerProviderStateMixin {
  /// Drives the chip from the tab it was on to the tab it is going to.
  late final AnimationController _slide;

  /// Drives the capsule between its two heights.
  late final AnimationController _collapse;

  /// Doubles, not ints: tapping a third tab mid-flight has to resume from
  /// where the chip actually is. Rounding to the nearest tab first would make
  /// it jump backwards before setting off again.
  late double _fromIndex;
  late double _toIndex;

  int get _index => AppDestinationX.navItems.indexOf(widget.destination);

  @override
  void initState() {
    super.initState();
    _fromIndex = _toIndex = math.max(0, _index).toDouble();
    _slide = AnimationController(vsync: this, value: 1)
      ..addListener(_repaint);
    _collapse = AnimationController(vsync: this)..addListener(_repaint);
    widget.collapsed.addListener(_onCollapsedChanged);
  }

  @override
  void didUpdateWidget(LiquidGlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsed != widget.collapsed) {
      oldWidget.collapsed.removeListener(_onCollapsedChanged);
      widget.collapsed.addListener(_onCollapsedChanged);
    }
    if (oldWidget.destination != widget.destination) {
      // Start from wherever the chip actually is, not from the tab we were
      // nominally on — tapping a third tab mid-flight should bend the chip
      // toward it, not teleport it back to restart.
      _fromIndex = lerpDouble(_fromIndex, _toIndex, _curvedSlide)!;
      _toIndex = math.max(0, _index).toDouble();
      _slide.forward(from: 0);
    }
  }

  void _repaint() => setState(() {});

  void _onCollapsedChanged() {
    final Duration duration = context.motion.fast;
    if (duration == Duration.zero) {
      _collapse.value = widget.collapsed.value ? 1 : 0;
      return;
    }
    _collapse.duration = duration;
    if (widget.collapsed.value) {
      _collapse.forward();
    } else {
      _collapse.reverse();
    }
  }

  double get _curvedSlide => AppMotion.spring.transform(_slide.value);

  @override
  void dispose() {
    widget.collapsed.removeListener(_onCollapsedChanged);
    _slide.dispose();
    _collapse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    _slide.duration = context.motion.base;

    // Apple's floating bars sit *inside* the home-indicator strip, not above
    // it — reserving the full 34pt leaves an obvious dead band underneath. On
    // a device with no indicator the subtraction floors at 10.
    final double lift = math.max(
      10,
      MediaQuery.paddingOf(context).bottom - 12,
    );

    final double height = lerpDouble(
      LiquidGlassNavBar.expandedHeight,
      LiquidGlassNavBar.collapsedHeight,
      _collapse.value,
    )!;
    final double radius = height / 2;

    return SizedBox(
      // Fixed. See the class doc — this is the number Scaffold measures and
      // republishes to every pane, and it must not move while the capsule
      // animates inside it.
      height: LiquidGlassNavBar.expandedHeight + lift,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          LiquidGlassNavBar.inset,
          0,
          LiquidGlassNavBar.inset,
          lift,
        ),
        child: Align(
          // Bottom, so the capsule shrinks toward the screen edge and its
          // distance from the home indicator stays put.
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: LiquidGlassNavBar.maxWidth,
            ),
            child: DecoratedBox(
              // Outside the glass, so the shadow falls on the page rather
              // than being clipped away with the refraction.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                // Two shadows, which is what actually reads as floating. A
                // single soft one only ever looks like a smudge under the
                // capsule: the wide ambient pass says the bar is well clear of
                // the page, and the tight contact pass under it is what the
                // eye uses to judge *how far*. One without the other reads as
                // either pasted on or hovering in nowhere.
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: 32,
                    spreadRadius: -4,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: palette.shadowContact,
                    blurRadius: 6,
                    spreadRadius: -2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: LiquidGlass(
                radius: radius,
                // Not the design file's Frost 4, deliberately. At Frost 4
                // over a 2% fill the page stayed *legible* through the bar —
                // you could read body text behind the glyphs — and the one
                // thing Apple's material is built to guarantee is that a
                // control stays readable over whatever scrolls beneath it.
                // Enough blur that content behind reads as colour and
                // movement, never as words.
                blurSigma: 26,
                // A vertical wash, 11% down to 3%, rather than the flat 12%
                // this carried. Flat-and-light was the single thing that made
                // the bar read as frosted plastic instead of glass: at a
                // uniform 12% the page behind it dies, the gradient rim has
                // only 23 points of white to separate itself from its own
                // fill, and the selection chip — brighter again by 8 — has
                // nowhere left to go.
                //
                // Averaged it is far more transparent than what it replaces,
                // so the blur goes up to 26 to keep the guarantee the old
                // comment was defending: content behind reads as colour and
                // movement, never as words. Brightest along the top edge
                // because that is where the rim is lit from, so the two agree
                // about where the light is.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.textPrimary.withValues(alpha: 0.11),
                    palette.textPrimary.withValues(alpha: 0.03),
                  ],
                ),
                child: SizedBox(
                  height: height,
                  child: Padding(
                    padding: const EdgeInsets.all(LiquidGlassNavBar.rim),
                    child: _Items(
                      destination: widget.destination,
                      onSelect: widget.onSelect,
                      chipIndex: lerpDouble(_fromIndex, _toIndex, _curvedSlide)!,
                      // Uncurved on purpose: the squash should peak halfway
                      // through the *journey*, not halfway through the eased
                      // value, which arrives early and reads as a flinch.
                      travel: _slide.value,
                      collapse: _collapse.value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The selection capsule and the row of glyphs that sits over it.
class _Items extends StatelessWidget {
  const _Items({
    required this.destination,
    required this.onSelect,
    required this.chipIndex,
    required this.travel,
    required this.collapse,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  /// Where the glow is, as a fractional tab index.
  final double chipIndex;

  /// 0 at the start of a move, 1 at the end. Drives the stretch.
  final double travel;

  final double collapse;

  /// The capsule's footprint. One tab of a 354pt bar is ~71pt wide, so this
  /// leaves a clear gutter either side rather than running its neighbours
  /// together.
  static const double _capsuleWidth = 58;
  static const double _capsuleHeight = 52;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = AppDestinationX.navItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double slot = constraints.maxWidth / items.length;

        // What makes it read as liquid rather than as a sliding shape: the
        // capsule stretches along its direction of travel and recovers,
        // peaking halfway. Zero at both ends, so at rest it is exactly its
        // nominal size.
        final double stretch = 1 + 0.42 * math.sin(math.pi * travel);
        final double capsuleWidth = math.min(
          _capsuleWidth * stretch,
          constraints.maxWidth,
        );
        final double capsuleHeight =
            lerpDouble(_capsuleHeight, 40, collapse)!;

        // Positioned rather than an Alignment, because Align's x maps through
        // the *free* space and would drift as the capsule stretches.
        final double left = (slot * (chipIndex + 0.5) - capsuleWidth / 2).clamp(
          0.0,
          math.max(0.0, constraints.maxWidth - capsuleWidth),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: left,
              top: (constraints.maxHeight - capsuleHeight) / 2,
              width: capsuleWidth,
              height: capsuleHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // A brighter tint and a rim over the bar's own fill — not a
                  // second backdrop filter. Nesting one would cost another
                  // snapshot to render a lens inside a lens, and glass inside
                  // glass is the thing Apple's own guidance is most explicit
                  // about avoiding. Colour alone did not carry the selection
                  // at a glance, which is why this is a shape again.
                  //
                  // 22% and a 38% rim, up from `glassFill`/`glassBorder`'s
                  // 8% and 25%. Measured off a screenshot, chip against bar
                  // goes from 56 vs 43 to 80 vs 25 — a separation of 13
                  // becoming one of 55. Both halves carry it: the chip comes
                  // up and the bar goes down by roughly as much.
                  color: palette.textPrimary.withValues(alpha: 0.22),
                  border: Border.all(
                    color: palette.textPrimary.withValues(alpha: 0.38),
                  ),
                  borderRadius: BorderRadius.circular(capsuleHeight / 2),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  Expanded(
                    child: _NavItem(
                      destination: item,
                      isSelected: item == destination,
                      onTap: () {
                        // Apple ticks on a tab change and stays silent when you
                        // tap the tab you are already on. A no-op off iOS.
                        if (item != destination) {
                          HapticFeedback.selectionClick();
                        }
                        onSelect(item);
                      },
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One destination.
///
/// The glyph goes `accentBright` rather than `accent` when selected, for the
/// reason recorded on the Windows bar: at 21pt, #7005BB is under WCAG AA on
/// this ground.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Center(
            // A colour tween rather than a cross-fade. `AnimatedSwitcher` and
            // friends push an Opacity layer, and a save layer anywhere above
            // the glass would leave its filter sampling that buffer instead
            // of the page — see LiquidGlass's doc.
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                // White at 72% unselected, not `textMuted`. #A4A4A4 was chosen
                // against the ground; over glass it is grey on grey, and the
                // reference keeps its unselected glyphs close to white.
                end: isSelected
                    ? palette.accentBright
                    : palette.textPrimary.withValues(alpha: 0.72),
              ),
              duration: context.motion.fast,
              curve: AppMotion.spring,
              builder: (context, colour, _) => Icon(
                // Heavier when selected. Swapped rather than tweened: two
                // families cannot interpolate, and a cross-fade between them
                // would need an Opacity layer, which is exactly what must not
                // appear above the glass.
                isSelected ? destination.selectedIcon : destination.icon,
                // Sized to the 71pt bar rather than the 56pt one it replaced.
                size: 26,
                color: colour,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
