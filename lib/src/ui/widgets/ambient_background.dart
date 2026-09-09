import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's ground: a flat slate fill under a soft white wash falling from
/// the top-left corner.
///
/// The wash is an overlay rather than the light end of a background ramp: a
/// literal `#FFFFFF`-to-`#1B252E` gradient across the window would leave the
/// upper half near-white, which is not the design.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(color: palette.background),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.40],
          ),
        ),
        child: child,
      ),
    );
  }
}
