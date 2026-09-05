import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// The three shortcut pills under the dashboard.
///
/// "Talk to Milo" is live — it opens the same end drawer the floating
/// launcher does. The other two are inert this pass: the dashboard is
/// frontend-only, and a pill that silently does nothing is better than one
/// wired to a half-built sheet.
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across once there is room for a ~150pt pill each, otherwise
        // stacked. At 393pt the pills would be 118pt and clip their labels.
        final horizontal = constraints.maxWidth >= 460;
        final actions = <Widget>[
          _ActionPill(
            icon: PhLight.sparkle,
            label: 'Talk to Milo',
            onTap: () => Scaffold.of(context).openEndDrawer(),
          ),
          const _ActionPill(icon: PhLight.plus, label: 'Add Task'),
          const _ActionPill(icon: PhLight.scan, label: 'Scan Notes'),
        ];

        if (!horizontal) {
          return Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                SizedBox(width: double.infinity, child: actions[i]),
                if (i < actions.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              Expanded(child: actions[i]),
              if (i < actions.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ActionPill extends StatefulWidget {
  const _ActionPill({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;

  /// Null renders the pill dimmed and unresponsive — the honest state for
  /// an action that has no destination yet.
  final VoidCallback? onTap;

  @override
  State<_ActionPill> createState() => _ActionPillState();
}

class _ActionPillState extends State<_ActionPill> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onTap != null;
    final tint = enabled ? palette.accent : palette.textMuted;

    final pill = Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tint.withValues(alpha: enabled ? 0.12 : 0.05),
          palette.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: enabled ? 0.28 : 0.14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 17, color: tint),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.typography.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: enabled ? palette.textPrimary : palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );

    if (!enabled) {
      return Semantics(
        button: true,
        enabled: false,
        label: '${widget.label}, not available yet',
        excludeSemantics: true,
        child: pill,
      );
    }

    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: context.motion.fast,
          curve: AppMotion.spring,
          child: pill,
        ),
      ),
    );
  }
}
