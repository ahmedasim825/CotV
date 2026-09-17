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

/// Whether the iOS control layer actually refracts, or just blurs.
///
/// The other escape hatch, and a profiling tool rather than a test one: a
/// fragment shader is pure shading area, and this app has measured before —
/// see `orb_field_background.dart` — that shading area, not blur, is what
/// costs it frames. Flipping this to `false` drops the refraction and leaves
/// everything else standing, which makes the shader's cost a single A/B
/// rather than an inference from a profile.
///
/// It is not the only thing that can turn the shader off. Impeller being
/// absent does too, silently, which is why the fallback has to look like a
/// deliberate material rather than a broken one.
final liquidGlassRefractionProvider = Provider<bool>((ref) => true);
