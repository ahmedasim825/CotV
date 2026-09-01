import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The "Double-Bezel" nested-hardware container: a translucent outer shell
/// (hairline border, faint fill) wrapping an inner core with its own fill
/// and a bright top edge simulating an inset highlight — like a glass plate
/// machined into a frosted tray. Every major surface in this app is built
/// from this instead of a flat Material [Card].
class GlassShell extends StatelessWidget {
  const GlassShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.outerRadius = 32,
    this.shellPadding = 6,
    this.tint,
    this.blurBackground = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final double outerRadius;
  final double shellPadding;
  final Color? tint;

  /// Set true only for surfaces that stay fixed on screen (e.g. the
  /// floating header) — backdrop blur is expensive to repaint continuously
  /// and must never sit inside scrolling content.
  final bool blurBackground;

  @override
  Widget build(BuildContext context) {
    final innerRadius = outerRadius - shellPadding;

    final core = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint ?? AppPalette.surface,
        borderRadius: BorderRadius.circular(innerRadius),
        border: Border.all(color: AppPalette.hairline),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 16)),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(innerRadius),
        border: const Border(
          top: BorderSide(color: AppPalette.innerHighlight),
        ),
      ),
      child: child,
    );

    final shell = Container(
      padding: EdgeInsets.all(shellPadding),
      decoration: BoxDecoration(
        color: AppPalette.glassFill,
        borderRadius: BorderRadius.circular(outerRadius),
        border: Border.all(color: AppPalette.glassBorder),
      ),
      child: core,
    );

    if (!blurBackground) return shell;

    return ClipRRect(
      borderRadius: BorderRadius.circular(outerRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: shell,
      ),
    );
  }
}
