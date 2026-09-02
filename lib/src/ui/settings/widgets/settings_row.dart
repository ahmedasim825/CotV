import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// A card of related settings rows, hairline-separated.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, thickness: 1, color: palette.hairline),
          ],
        ],
      ),
    );
  }
}

/// The shared skeleton of every row: an accent glyph, a title with an
/// optional explanation, and a trailing control.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconTint,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconTint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = iconTint ?? palette.accent;

    final row = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: tint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.typography.ui(
                      size: 14,
                      weight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
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
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );

    if (onTap == null || !enabled) return row;

    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }
}

/// A row whose control is a switch.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  /// Shows a spinner in place of the switch while the change is in flight —
  /// a biometric prompt can sit on screen for seconds.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      iconTint: value && enabled ? palette.accent : palette.textMuted,
      trailing: busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.accent,
              ),
            )
          : Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: palette.onAccent,
              activeTrackColor: palette.accent,
              inactiveThumbColor: palette.textMuted,
              inactiveTrackColor: palette.glassFill,
            ),
    );
  }
}

/// A row that opens something else — a picker sheet, a system dialog. The
/// current value sits on the right with a disclosure caret.
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      enabled: enabled,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: context.typography.ui(
                  size: 12.5,
                  color: palette.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(PhLight.caretRight, size: 13, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
