import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the ground's orb field actually animates.
///
/// The escape hatch for tests. The field's drift ticker repeats for as long as
/// it is mounted, so the tree never comes to rest and `pumpAndSettle` runs to
/// its ten-minute timeout instead of returning. The tests that build the real
/// app override this to `false`; everything else never reaches the ground.
///
/// Reduced motion is handled separately, at the widget, so that flipping this
/// off in a test does not also claim the user asked for less motion.
final ambientAnimationProvider = Provider<bool>((ref) => true);
