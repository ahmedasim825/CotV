import 'package:flutter/material.dart';

import '../../food/food_route.dart';
import '../../food/food_search_screen.dart';
import '../../tasks/task_form_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// The three shortcut pills under the dashboard.
///
/// "Talk to Milo" opens the end drawer, "Add Task" the same sheet the Tasks
/// screen's quick-add does, and "Log Food" the food logger. Each is the
/// screen's own entry point rather than a second implementation of it.
///
/// Milo leads, filled rather than outlined: it used to share the job with a
/// floating launcher pinned over the corner of every screen, and now that
/// the launcher is gone this row is the way in. The other two stay outlined
/// so the group still reads as one primary action and two shortcuts.
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
            filled: true,
            onTap: () => Scaffold.of(context).openEndDrawer(),
          ),
          _ActionPill(
            icon: PhLight.plus,
            label: 'Add Task',
            onTap: () => showTaskFormSheet(context),
          ),
          _ActionPill(
            icon: PhLight.forkKnife,
            label: 'Log Food',
            onTap: () => pushFoodPage(context, const FoodSearchScreen()),
          ),
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
  const _ActionPill({
    required this.icon,
    required this.label,
    this.filled = false,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// Draws the pill as the group's primary action: an accent fill with
  /// [AppPalette.onAccent] contents, rather than an accent-washed outline.
  final bool filled;

  /// Null renders the pill dimmed and unresponsive — the honest state for
  /// an action that has no destination yet.
  final VoidCallback? onTap;

  @override
  State<_ActionPill> createState() => _ActionPillState();
}

class _ActionPillState extends State<_ActionPill> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (widget.onTap == null) return;
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final motion = context.motion;
    final enabled = widget.onTap != null;
    final tint = enabled ? palette.accent : palette.textMuted;
    final filled = widget.filled && enabled;

    final Color background;
    final Color foreground;
    final Color border;
    if (filled) {
      // Brightening on hover rather than only glowing: on Titanium and
      // Monochrome the glow barely separates from the surface, and the fill
      // is the only thing there that can carry the state.
      background = _hovered ? palette.accentBright : palette.accent;
      foreground = palette.onAccent;
      border = Colors.transparent;
    } else {
      background = Color.alphaBlend(
        tint.withValues(alpha: enabled ? (_hovered ? 0.20 : 0.12) : 0.05),
        palette.surface,
      );
      foreground = enabled ? palette.textPrimary : palette.textMuted;
      border = tint.withValues(alpha: enabled ? (_hovered ? 0.45 : 0.28) : 0.14);
    }

    final pill = AnimatedContainer(
      duration: motion.hover,
      curve: Curves.easeOut,
      height: 52,
      transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          if (_hovered)
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: -2,
            ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.icon,
            size: 17,
            color: filled ? palette.onAccent : tint,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.typography.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: foreground,
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: motion.fast,
            curve: AppMotion.spring,
            child: pill,
          ),
        ),
      ),
    );
  }
}
