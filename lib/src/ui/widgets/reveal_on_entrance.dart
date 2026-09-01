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

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: ImageFiltered(
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
