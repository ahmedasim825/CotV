import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/clock_providers.dart';
import '../../../providers/prayer_providers.dart' show startOfDay;
import '../../../providers/selected_date_providers.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eyebrow_pill.dart';
import '../../widgets/ph_light_icons.dart';

/// Day-by-day navigation for the schedule: arrows either side of the date,
/// plus a calendar picker for jumping further.
///
/// Horizontal swipes over the timeline are handled by the schedule view
/// itself, which calls the same [SelectedDateNotifier] methods, so the two
/// gestures can't disagree about what "next day" means.
class DateNavigationHeader extends ConsumerWidget {
  const DateNavigationHeader({super.key, this.dense = false});

  /// Tightens spacing for the narrower master pane on iPad.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDateProvider);
    final today = startOfDay(ref.watch(currentMinuteProvider));
    final relative = relativeDayName(selected, today);

    return Row(
      children: [
        _NavArrow(
          icon: PhLight.caretLeft,
          semanticLabel: 'Previous day',
          onTap: () => ref.read(selectedDateProvider.notifier).previousDay(),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openDatePicker(context, ref, selected),
            child: Column(
              children: [
                if (relative != null) ...[
                  EyebrowPill(label: relative.toUpperCase()),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        dense ? formatShortDate(selected) : formatFullDate(selected),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.display(
                          size: dense ? 20 : 24,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      PhLight.calendarDots,
                      size: 16,
                      color: AppPalette.textMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _NavArrow(
          icon: PhLight.caretRight,
          semanticLabel: 'Next day',
          onTap: () => ref.read(selectedDateProvider.notifier).nextDay(),
        ),
      ],
    );
  }

  Future<void> _openDatePicker(
    BuildContext context,
    WidgetRef ref,
    DateTime selected,
  ) async {
    final today = startOfDay(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      // Prayer times are computed on demand for any date, so the range only
      // needs to be wide enough to be practically unbounded.
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 2, 12, 31),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppPalette.amber,
                onPrimary: AppPalette.onAmber,
                surface: AppPalette.surface,
              ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      ref.read(selectedDateProvider.notifier).select(picked);
    }
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // 44pt: Apple's minimum comfortable touch target.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppPalette.glassBorder,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: AppPalette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
