import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/theme_providers.dart';
import '../../../providers/user_settings_providers.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// The theme gallery.
///
/// Each card previews the theme it offers using that theme's own tokens
/// rather than the active ones, so the grid shows six genuinely different
/// surfaces side by side instead of six labels. Selecting one writes
/// [UserSettings.themeId]; `MaterialApp` cross-fades the whole app to it.
class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key, this.columns = 2});

  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(themeVariantProvider);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: AppThemeVariant.values.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 156,
      ),
      itemBuilder: (context, index) {
        final variant = AppThemeVariant.values[index];
        return _ThemeCard(
          variant: variant,
          isSelected: variant == active,
          onTap: () => ref
              .read(userSettingsControllerProvider.notifier)
              .setThemeId(variant.id),
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.variant,
    required this.isSelected,
    required this.onTap,
  });

  final AppThemeVariant variant;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The card's chrome comes from the *active* theme so it sits in the
    // page; only the preview inside uses the offered theme's palette.
    final active = context.palette;
    final preview = variant.palette;

    return CustomCard(
      onTap: onTap,
      accent: preview.accent,
      selected: isSelected,
      padding: const EdgeInsets.all(10),
      semanticLabel: '${variant.label} theme. ${variant.tagline}.'
          '${isSelected ? ' Currently active.' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _ThemeSwatch(palette: preview)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  variant.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: active.textPrimary,
                  ),
                ),
              ),
              if (isSelected)
                Icon(PhLight.checkCircle, size: 15, color: preview.accent),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            variant.tagline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typography.ui(size: 10.5, color: active.textMuted),
          ),
        ],
      ),
    );
  }
}

/// A miniature of the theme: its canvas, a card on that canvas, a line of
/// text and its accent — the four decisions that actually distinguish one
/// palette from another.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: palette.background,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: palette.hairline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.textPrimary.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 12,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 14,
                    height: 12,
                    decoration: BoxDecoration(
                      color: palette.secondary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: palette.surfaceRaised,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
