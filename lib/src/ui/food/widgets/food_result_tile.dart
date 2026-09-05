import 'package:flutter/material.dart';

import '../../../models/food_models.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eyebrow_pill.dart';
import '../../widgets/ph_light_icons.dart';
import 'food_thumbnail.dart';

/// One row of the search results.
///
/// Everything shown is quoted per 100 g, which is the basis both food
/// databases return and the only one two rows from different sources can
/// be compared on.
class FoodResultTile extends StatelessWidget {
  const FoodResultTile({super.key, required this.hit, required this.onTap});

  final FoodSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final subtitle = _subtitle();

    return CustomCard(
      padding: const EdgeInsets.all(12),
      radius: 18,
      elevated: false,
      onTap: onTap,
      semanticLabel: '${hit.name}, $subtitle, from ${hit.source.label}',
      child: Row(
        children: [
          FoodThumbnail(url: hit.thumbUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.ui(
                          size: 14.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Which database answered. Two rows can carry the same
                    // food name with different numbers behind them, and
                    // this is what tells them apart.
                    EyebrowPill(
                      label: hit.source.label,
                      color: hit.source == FoodDataSource.usda
                          ? palette.accent
                          : palette.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _macroLine(),
                  maxLines: 1,
                  // Six figures will not fit a narrow phone. That is fine:
                  // the row is a preview, and the configurator shows all
                  // seven nutrients in full.
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 11,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(PhLight.caretRight, size: 14, color: palette.textMuted),
        ],
      ),
    );
  }

  /// Brand where there is one, then the calorie headline.
  String _subtitle() {
    final brand = hit.brandName;
    final calories = '${hit.caloriesPer100g.round()} kcal / 100 g';
    return brand == null || brand.isEmpty ? calories : '$brand · $calories';
  }

  /// The macros, fiber, and the two micronutrients, per 100 g.
  String _macroLine() {
    final n = hit.item.per100g;
    return 'P ${n.protein.toStringAsFixed(1)}g · '
        'C ${n.carbs.toStringAsFixed(1)}g · '
        'F ${n.fat.toStringAsFixed(1)}g · '
        'Fib ${n.fiber.toStringAsFixed(1)}g · '
        'Na ${n.sodium.round()}mg · '
        'K ${n.potassium.round()}mg';
  }
}
