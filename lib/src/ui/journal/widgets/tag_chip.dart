import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// A journal tag, in all three places one appears: read-only on an entry
/// card, selectable in the filter row, and removable in the writer.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.showHash = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// When set, the chip grows a trailing dismiss control.
  final VoidCallback? onRemove;

  final bool showHash;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = selected ? palette.onAccent : palette.textSecondary;

    final chip = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.spring,
      padding: EdgeInsets.only(
        left: 10,
        right: onRemove != null ? 5 : 10,
        top: 5,
        bottom: 5,
      ),
      decoration: BoxDecoration(
        color: selected ? palette.accent : palette.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? palette.accent : palette.glassBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            showHash ? '#$label' : label,
            style: context.typography.ui(
              size: 11.5,
              weight: FontWeight.w600,
              color: foreground,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: 'Remove tag $label',
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(PhLight.x, size: 11, color: foreground),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return chip;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Tag $label',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: chip,
      ),
    );
  }
}
