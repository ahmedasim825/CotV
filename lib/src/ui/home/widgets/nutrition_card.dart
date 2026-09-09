import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/nutrition_providers.dart';
import '../../components/components.dart';
import '../../food/food_route.dart';
import '../../food/food_search_screen.dart';
import '../../study/widgets/study_timer_card.dart' show CountdownRing;
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// One macro's progress against its target.
class _Macro {
  const _Macro(this.name, this.grams, this.target);

  final String name;
  final double grams;
  final int target;
}

/// Calories as a ring, macros as three bars beneath it.
///
/// Tapping the card opens the food logger; anything added there lands in
/// [dailyNutritionProvider] and is reflected here on the next frame.
class NutritionCard extends ConsumerWidget {
  const NutritionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final log = ref.watch(dailyNutritionProvider);
    final totals = log.totals;
    final targets = ref.watch(nutritionTargetsProvider);

    final eaten = totals.calories.round();
    final macros = [
      _Macro('Protein', totals.protein, targets.protein),
      _Macro('Carbs', totals.carbs, targets.carbs),
      _Macro('Fats', totals.fat, targets.fat),
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      onTap: () => pushFoodPage(context, const FoodSearchScreen()),
      semanticLabel: 'Nutrition, $eaten of ${targets.calories} kilocalories. '
          'Open the food logger.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhLight.forkKnife, size: 18, color: palette.secondary),
              const SizedBox(width: 10),
              Text(
                'Nutrition',
                style: context.typography.ui(size: 15, weight: FontWeight.w600),
              ),
              const Spacer(),
              Icon(PhLight.plusCircle, size: 18, color: palette.textMuted),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: CountdownRing(
              progress: eaten / targets.calories,
              accent: palette.secondary,
              diameter: 132,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$eaten',
                    style: context.typography.display(
                      size: 30,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'of ${targets.calories} kcal',
                    style: context.typography.ui(
                      size: 11,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (log.isEmpty)
            // The ring at zero is already honest; this says whether that is
            // a day not started or a day the log failed to load.
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: Text(
                  'Nothing logged yet',
                  style: context.typography.ui(
                    size: 12.5,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          for (var i = 0; i < macros.length; i++) ...[
            _MacroBar(macro: macros[i]),
            if (i < macros.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.macro});

  final _Macro macro;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final value = (macro.grams / macro.target).clamp(0.0, 1.0);
    final grams = macro.grams.round();

    return Semantics(
      label: '${macro.name}, $grams of ${macro.target} grams',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  macro.name,
                  style: context.typography.ui(size: 12.5),
                ),
              ),
              Text(
                '$grams / ${macro.target}g',
                style: context.typography.ui(
                  size: 12,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          MeterBar(value: value, color: palette.accent),
        ],
      ),
    );
  }
}
