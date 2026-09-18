import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';

import '../../platform/sf_symbols.dart';
import '../../theme/app_theme.dart';

/// A Cupertino switch that is the real `UISwitch` where one exists.
///
/// [CNSwitch] already falls back on its own, but only usefully on Apple
/// platforms: below iOS 26 it hands off to [CupertinoSwitch] with the tint
/// carried over, while off Apple platforms entirely it returns a bare Material
/// [Switch] with no colour parameters passed through at all. That last path is
/// the one `tool/tasks_preview.dart` runs, so without this wrapper the toggles
/// come up as Material controls in the theme's default tint rather than the
/// accent the design asks for — on the exact surface the design is checked on.
///
/// Gated on [hasSFSymbols] rather than [ThemeData.platform] for the reason
/// documented there: the package picks its own path from `Platform.isIOS`, and
/// a gate reading the faked theme would disagree with it precisely under
/// `flutter_test` and in the Windows preview.
class NativeSwitch extends StatelessWidget {
  const NativeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.controller,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Held by the caller, one per toggle, so the switch can be driven
  /// imperatively as well as rebuilt — turning Time on has to move the Date
  /// switch under it without waiting for a frame.
  final CNSwitchController? controller;

  @override
  Widget build(BuildContext context) {
    final accent = context.palette.accent;

    if (hasSFSymbols) {
      return CNSwitch(
        value: value,
        onChanged: onChanged,
        controller: controller,
        color: accent,
        // The UISwitch is 51x31. The package's default of 44 is a touch
        // target, not a control size, and it renders the switch oversized
        // beside a 13.5pt label.
        height: 31,
      );
    }

    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: accent,
    );
  }
}
