import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../study/widgets/study_timer_card.dart' show CountdownRing;
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// One macro's progress against its target. Mock only.
class _Macro {
  const _Macro(this.name, this.grams, this.target);

  final String name;
  final int grams;
  final int target;
}

const int _caloriesEaten = 1417;
const int _calorieTarget = 2000;

const List<_Macro> _mockMacros = [
  _Macro('Protein', 96, 150),
  _Macro('Carbs', 158, 220),
  _Macro('Fats', 47, 70),
];

/// Calories as a ring, macros as three bars beneath it.
class NutritionCard extends StatelessWidget {
  const NutritionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: CountdownRing(
              progress: _caloriesEaten / _calorieTarget,
              accent: palette.secondary,
              diameter: 132,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_caloriesEaten',
                    style: context.typography.display(size: 30),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'of $_calorieTarget kcal',
                    style: context.typography.ui(
                      size: 11,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _mockMacros.length; i++) ...[
            _MacroBar(macro: _mockMacros[i]),
            if (i < _mockMacros.length - 1) const SizedBox(height: 12),
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

    return Semantics(
      label: '${macro.name}, ${macro.grams} of ${macro.target} grams',
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
                '${macro.grams} / ${macro.target}g',
                style: context.typography.ui(
                  size: 12,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: palette.glassFill,
              valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
            ),
          ),
        ],
      ),
    );
  }
}
