import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'primary_button.dart';

/// Asks the user to confirm something irreversible — deleting a habit,
/// discarding an unsaved task.
///
/// Resolves to true only on an explicit confirm; dismissing by scrim, back
/// gesture or Cancel all resolve to false, so a caller can treat anything
/// other than true as "do nothing".
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  IconData? confirmIcon,
}) async {
  final palette = context.palette;

  final result = await showDialog<bool>(
    context: context,
    barrierColor: palette.scrim,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.glassBorder),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.typography.display(size: 22, weight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: context.typography.ui(
                  size: 13.5,
                  color: palette.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: cancelLabel,
                      variant: ButtonVariant.outline,
                      expand: true,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: confirmLabel,
                      icon: confirmIcon,
                      variant: ButtonVariant.danger,
                      expand: true,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  return result ?? false;
}
