import 'package:flutter/material.dart';

import '../../../models/food_models.dart';
import '../../theme/app_theme.dart';

/// The seven-nutrient breakdown, shown wherever a portion has been resolved
/// to numbers.
///
/// Shared by the serving configurator and the recipe builder so both round
/// and label identically — calories to the whole number, macros to one
/// decimal, micronutrients to the whole milligram.
class MacroReadout extends StatelessWidget {
  const MacroReadout({
    super.key,
    required this.totals,
    this.caption,
    this.accent,
  });

  final NutritionTotals totals;

  /// A line above the grid, e.g. "Per serving".
  final String? caption;

  /// Tints the calorie figure. Defaults to the theme accent.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = accent ?? palette.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null) ...[
          Text(
            caption!.toUpperCase(),
            style: context.typography.eyebrow(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              totals.calories.round().toString(),
              style: context.typography.display(size: 34, color: tint),
            ),
            const SizedBox(width: 8),
            Text(
              'kcal',
              style: context.typography.ui(size: 13, color: palette.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // Six cells now, so three across on a wide pane and two on a
            // phone — both divide evenly. Five would strand one cell
            // alone on a second row.
            final columns = constraints.maxWidth >= 460 ? 3 : 2;
            final spacing = 12.0;
            final cellWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: 14,
              children: [
                for (final nutrient in _nutrientsOf(totals))
                  SizedBox(
                    width: cellWidth,
                    child: _NutrientCell(nutrient: nutrient),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<_Nutrient> _nutrientsOf(NutritionTotals totals) => [
        _Nutrient('Protein', totals.protein, 'g'),
        _Nutrient('Carbs', totals.carbs, 'g'),
        _Nutrient('Fiber', totals.fiber, 'g'),
        _Nutrient('Fat', totals.fat, 'g'),
        _Nutrient('Sodium', totals.sodium, 'mg'),
        _Nutrient('Potassium', totals.potassium, 'mg'),
      ];
}

class _Nutrient {
  const _Nutrient(this.label, this.value, this.unit);

  final String label;
  final double value;
  final String unit;

  /// Grams to one decimal, milligrams whole — a tenth of a milligram of
  /// sodium is noise the database itself does not carry.
  String get formatted => unit == 'g'
      ? '${value.toStringAsFixed(1)}$unit'
      : '${value.round()}$unit';
}

class _NutrientCell extends StatelessWidget {
  const _NutrientCell({required this.nutrient});

  final _Nutrient nutrient;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      label: '${nutrient.label}, ${nutrient.formatted}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nutrient.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typography.ui(size: 11.5, color: palette.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            nutrient.formatted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typography.ui(size: 15, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
