import 'package:flutter/material.dart';

import '../../../models/food_models.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import 'food_thumbnail.dart';

/// One row of the search results.
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
      semanticLabel: subtitle == null ? hit.name : '${hit.name}, $subtitle',
      child: Row(
        children: [
          FoodThumbnail(url: hit.thumbUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(size: 14.5, weight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
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
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(PhLight.caretRight, size: 14, color: palette.textMuted),
        ],
      ),
    );
  }

  /// Brand, serving and calories, in whichever combination the endpoint
  /// actually returned — a common food has no brand and no calories.
  String? _subtitle() {
    final parts = <String>[
      if (hit.brandName != null && hit.brandName!.isNotEmpty) hit.brandName!,
      if (hit.servingPreview != null) hit.servingPreview!,
      if (hit.caloriesPreview != null)
        '${hit.caloriesPreview!.round()} kcal',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
