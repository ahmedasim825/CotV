import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/ph_light_icons.dart';

/// Pushes a food-logger screen onto the root navigator.
///
/// The food flow is the one place in this app that pushes routes — every
/// other screen is an [AppShell] destination or a modal sheet. The chrome a
/// pushed page needs (its own [Scaffold], the ambient background, the safe
/// area) is supplied here rather than by each screen, so the same widget
/// renders correctly whether it was pushed or is being shown as the Food
/// tab's pane.
Future<T?> pushFoodPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    MaterialPageRoute<T>(
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: AmbientBackground(
          // The pages draw their own bottom padding, as the panes do.
          child: SafeArea(bottom: false, child: page),
        ),
      ),
    ),
  );
}

/// A back control for a pushed food page.
///
/// Renders nothing when there is nothing to pop, which is what lets
/// [FoodSearchScreen] be both the Food tab's pane and a pushed page without
/// a flag threading through it.
class FoodBackButton extends StatelessWidget {
  const FoodBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();
    final palette = context.palette;

    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: minTouchTarget,
          height: minTouchTarget,
          child: Icon(PhLight.arrowLeft, size: 20, color: palette.textSecondary),
        ),
      ),
    );
  }
}
