import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fades, lifts and de-blurs [child] into place once, after [delay] — the
/// Flutter equivalent of a scroll-triggered `translate-y-16 blur-md
/// opacity-0 -> translate-y-0 blur-0 opacity-100` reveal. Driving it from a
/// one-shot [AnimationController] (transform + opacity + a paint-only blur
/// filter) keeps it off the layout pass entirely, so it stays GPU-cheap even
/// stacked across many cards.
class RevealOnEntrance extends StatefulWidget {
  const RevealOnEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<RevealOnEntrance> createState() => _RevealOnEntranceState();
}

class _RevealOnEntranceState extends State<RevealOnEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.spring,
  );

  bool _scheduled = false;

  /// Scheduled here rather than in [initState] because the decision needs
  /// [Theme], and [initState] runs before this widget may depend on one.
  ///
  /// Skipping the timer, not just the animation, is the point: a reveal that
  /// will never be drawn should not leave a pending [Future.delayed] behind
  /// it. `flutter_test` fails a test outright for a timer still pending at
  /// teardown, so scheduling one here and ignoring it in [build] would make
  /// every iOS widget test fail on a timer it had no reason to create.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled || !_revealsAtAll(context)) return;
    _scheduled = true;
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Whether this widget animates at all in its current surroundings.
  ///
  /// Two independent reasons it might not, and both have to be settled before
  /// the timer is scheduled as well as before the frame is built:
  ///
  ///   * the platform asks for reduced motion, or
  ///   * this is the glass path, where the [Opacity] below would be a save
  ///     layer and a [BackdropFilter] beneath a save layer samples that buffer
  ///     instead of the page — so every glass card under a running reveal
  ///     would blur nothing at all. Standing down is cheaper than the
  ///     alternatives (`BlendMode.src` changes how the fill composites;
  ///     dropping only the `Opacity` keeps two of the three layers) and costs
  ///     little, since iOS arrives at this screen through its own push
  ///     transition — the entrance the stagger was imitating.
  static bool _revealsAtAll(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return false;
    return !context.useLiquidGlass;
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to reveal: the child is already in its final position, so show
    // it there. See [_revealsAtAll] for the two reasons.
    if (!_revealsAtAll(context)) return widget.child;

    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: ImageFiltered(
              // A zero-sigma blur is not a no-op. `ImageFiltered` pushes an
              // `ImageFilterLayer` whenever it is enabled, whatever the
              // filter — `alwaysNeedsCompositing => child != null && enabled`
              // — so leaving it on after the reveal settles left every
              // revealed section holding a live filter layer for the life of
              // the screen. Twelve of them across Home and Prayers.
              //
              // Toggled rather than unwrapped: dropping the widget at t == 1
              // would change the tree's shape and dispose the child's State
              // with it.
              enabled: t < 1,
              imageFilter: ImageFilter.blur(
                sigmaX: 5 * (1 - t),
                sigmaY: 5 * (1 - t),
              ),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
