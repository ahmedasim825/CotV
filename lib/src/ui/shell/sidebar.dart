import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// How much of the sidebar is showing.
enum SidebarMode {
  /// Icons and labels.
  expanded,

  /// Icons only.
  collapsed,

  /// Nothing — the content pane takes the full window, and a floating
  /// control in [AppShell] brings it back.
  hidden;

  double get width {
    switch (this) {
      case SidebarMode.expanded:
        return 188;
      case SidebarMode.collapsed:
        return 72;
      case SidebarMode.hidden:
        return 0;
    }
  }

  bool get showsLabels => this == SidebarMode.expanded;
}

/// The left rail: two width controls, five destinations, the Milo dock and a
/// settings gear.
///
/// The dock is passed in rather than built here so this file stays layout and
/// the dock keeps its own provider watches.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.mode,
    required this.destination,
    required this.onSelect,
    required this.onToggleCollapse,
    required this.onToggleHidden,
    this.dock,
  });

  final SidebarMode mode;
  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;
  final VoidCallback onToggleCollapse;
  final VoidCallback onToggleHidden;

  /// The Milo section. Null until Task 4 supplies it.
  final Widget? dock;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedContainer(
      duration: context.motion.fast,
      curve: AppMotion.spring,
      width: mode.width,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.hairline)),
      ),
      // Below the collapsed width the row contents overflow mid-animation;
      // clipping is cheaper than rebuilding each row against the live width.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: mode.width,
          maxWidth: mode.width == 0 ? SidebarMode.collapsed.width : mode.width,
          child: Padding(
            padding: EdgeInsets.only(
              top: 18,
              bottom: 18 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeaderControls(
                  mode: mode,
                  onToggleCollapse: onToggleCollapse,
                  onToggleHidden: onToggleHidden,
                ),
                const SizedBox(height: 22),
                for (final item in AppDestinationX.navItems)
                  SidebarNavItem(
                    destination: item,
                    isSelected: item == destination,
                    showLabel: mode.showsLabels,
                    onTap: () => onSelect(item),
                  ),
                const Spacer(),
                if (dock != null) ...[
                  Divider(color: palette.hairline, height: 1, indent: 16, endIndent: 16),
                  const SizedBox(height: 14),
                  dock!,
                ],
                const SizedBox(height: 10),
                _FooterGear(
                  isSelected: destination == AppDestination.settings,
                  onTap: () => onSelect(AppDestination.settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One destination row.
///
/// Selection reads three ways at once, because the accent is a deep violet on
/// a slate ground and on its own it is a weak signal at 13pt: the glyph and
/// the label both take [AppPalette.accent], and a 2pt bar appears under the
/// glyph.
class SidebarNavItem extends StatelessWidget {
  const SidebarNavItem({
    super.key,
    required this.destination,
    required this.isSelected,
    required this.showLabel,
    required this.onTap,
  });

  final AppDestination destination;
  final bool isSelected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = isSelected ? palette.accent : palette.textMuted;

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      child: Tooltip(
        message: showLabel ? '' : destination.label,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
            child: SizedBox(
              height: minTouchTarget,
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(destination.icon, size: 19, color: color),
                      const SizedBox(height: 4),
                      // Reserved whether or not it is drawn, so selecting a
                      // row does not nudge the icons up by two points.
                      SizedBox(
                        height: 2,
                        width: 21,
                        child: isSelected
                            ? DecoratedBox(
                                key: const ValueKey('sidebar-underline'),
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  if (showLabel) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.ui(
                          size: 14,
                          weight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderControls extends StatelessWidget {
  const _HeaderControls({
    required this.mode,
    required this.onToggleCollapse,
    required this.onToggleHidden,
  });

  final SidebarMode mode;
  final VoidCallback onToggleCollapse;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget button(IconData icon, VoidCallback onTap, String tip) {
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: minTouchTarget,
            height: minTouchTarget,
            child: Icon(icon, size: 22, color: palette.textSecondary),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: mode.showsLabels
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: [
          button(PhLight.list, onToggleCollapse,
              mode.showsLabels ? 'Collapse sidebar' : 'Expand sidebar'),
          if (mode.showsLabels)
            button(PhLight.sidebarSimple, onToggleHidden, 'Hide sidebar'),
        ],
      ),
    );
  }
}

class _FooterGear extends StatelessWidget {
  const _FooterGear({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: 'Settings',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: minTouchTarget,
              height: minTouchTarget,
              child: Icon(
                PhLight.gear,
                size: 20,
                color: isSelected ? palette.accent : palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
