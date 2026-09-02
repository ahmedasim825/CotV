import 'package:flutter/material.dart';

import '../components/components.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// One choice in an [showOptionPicker] sheet.
@immutable
class PickerOption<T> {
  const PickerOption({required this.value, required this.label, this.note});

  final T value;
  final String label;

  /// The detail that makes the choice meaningful — an angle, a duration.
  final String? note;
}

/// A single-select list in a sheet, for settings with more options than fit
/// in a segmented control.
///
/// Resolves to the chosen value, or null if the sheet was dismissed —
/// selecting closes it immediately, since there is nothing else to confirm.
Future<T?> showOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  required T selected,
  String? subtitle,
}) {
  return showStandardBottomSheet<T>(
    context,
    // Read-only list, so dragging it away is the natural way to back out.
    enableDrag: true,
    builder: (sheetContext) => StandardBottomSheet(
      title: title,
      subtitle: subtitle,
      heightFactor: 0.85,
      child: Column(
        children: [
          for (final option in options) ...[
            _OptionRow<T>(
              option: option,
              isSelected: option.value == selected,
              onTap: () => Navigator.of(sheetContext).pop(option.value),
            ),
            if (option != options.last) const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final PickerOption<T> option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: option.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: AppMotion.spring,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? palette.accentSoft : palette.glassFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? palette.accent : palette.glassBorder,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: context.typography.ui(
                        size: 14,
                        weight: FontWeight.w600,
                        color: isSelected
                            ? palette.accent
                            : palette.textPrimary,
                      ),
                    ),
                    if (option.note != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        option.note!,
                        style: context.typography.ui(
                          size: 11.5,
                          color: palette.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 12),
                Icon(PhLight.checkCircle, size: 18, color: palette.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
