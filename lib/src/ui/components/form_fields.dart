import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The shared decoration for every text input in the app, so a habit's
/// title field, a journal tag field and a task's description all read as
/// the same control.
InputDecoration appInputDecoration(
  BuildContext context, {
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  EdgeInsets contentPadding =
      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
}) {
  final palette = context.palette;

  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color),
      );

  return InputDecoration(
    hintText: hint,
    hintStyle: context.typography.ui(size: 14, color: palette.textMuted),
    filled: true,
    fillColor: palette.glassFill,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: contentPadding,
    border: border(palette.glassBorder),
    enabledBorder: border(palette.glassBorder),
    focusedBorder: border(palette.accent),
    errorBorder: border(palette.danger),
    focusedErrorBorder: border(palette.danger),
    errorStyle: context.typography.ui(size: 11.5, color: palette.danger),
  );
}

/// The tracked-out caption that labels a form field, with an accent glyph
/// and an optional "optional" marker.
class FieldLabel extends StatelessWidget {
  const FieldLabel({
    super.key,
    required this.icon,
    required this.label,
    this.optional = false,
    this.accent,
  });

  final IconData icon;
  final String label;
  final bool optional;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Icon(icon, size: 13, color: accent ?? palette.accent),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: context.typography.eyebrow(color: palette.textSecondary),
        ),
        if (optional) ...[
          const SizedBox(width: 8),
          Text(
            'OPTIONAL',
            style: context.typography.eyebrow(color: palette.textMuted),
          ),
        ],
      ],
    );
  }
}
