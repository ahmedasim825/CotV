import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../../../models/task_list_filter.dart';
import '../../theme/app_theme.dart';

/// The `All ⌄` control at the head of the tasks list.
///
/// A native `UIMenu` on iOS 26, which is most of why it is worth reaching for
/// the package here rather than building a dropdown: the menu brings its own
/// background blur, its own presentation animation and the system's own
/// checkmark, none of which a Flutter popup gets close to. The button's label
/// is SF Pro because the button is drawn by UIKit.
///
/// Off Apple platforms — and on any iOS below 26 — the package falls back to a
/// `CupertinoActionSheet`: a modal from the bottom rather than a dropdown
/// anchored to the button. It works and it is reachable, and it looks nothing
/// like the design.
///
/// That fallback renders **labels only**. It drops `tint`, `icon` and
/// `customIcon` on the floor, so the sheet comes up in the theme's own accent
/// with no glyphs beside Tasks and Reminders. Worth knowing before trying to
/// fix either here: there is no seam, and supplying a Phosphor `customIcon`
/// the way the nav bar does would be dead weight, because the only path that
/// would want one is the path that ignores it.
class TaskFilterMenu extends StatelessWidget {
  const TaskFilterMenu({
    super.key,
    required this.active,
    required this.onSelected,
  });

  final TaskListFilter active;
  final ValueChanged<TaskListFilter> onSelected;

  /// Where the divider falls: after the three time filters, before the two
  /// kind filters. The design groups them without a heading, so the rule is
  /// the only thing saying these answer different questions.
  static const int _dividerAfter = 3;

  @override
  Widget build(BuildContext context) {
    final entries = <CNPopupMenuEntry>[];

    // Built alongside the entries so the callback can read a filter straight
    // off the index. The package reports the position within `items`, and a
    // divider occupies one — on both its native and its action-sheet path —
    // so a null here is the divider and means "nothing was chosen".
    final filterAt = <TaskListFilter?>[];

    for (var i = 0; i < TaskListFilter.values.length; i++) {
      if (i == _dividerAfter) {
        entries.add(const CNPopupMenuDivider());
        filterAt.add(null);
      }

      final filter = TaskListFilter.values[i];
      final symbol = filter.sfSymbol;

      entries.add(
        CNPopupMenuItem(
          label: filter.label,
          checked: filter == active,
          // Unconditional: the only path that draws this is the native one,
          // which by definition has the symbols. See the class doc for why
          // there is no `customIcon` beside it.
          icon: symbol == null ? null : CNSymbol(symbol, size: 17),
        ),
      );
      filterAt.add(filter);
    }

    return Semantics(
      button: true,
      label: 'Filter: ${active.label}',
      child: CNPopupMenuButton(
        buttonLabel: active.label,
        // White, not the accent. The tint colours the button's label *and* the
        // menu's checkmark and symbols, and the design draws all three plain —
        // this control reports what you are looking at rather than offering an
        // action, so colouring it would give it a weight it has not earned.
        tint: context.palette.textPrimary,
        items: entries,
        onSelected: (index) {
          if (index < 0 || index >= filterAt.length) return;
          final filter = filterAt[index];
          if (filter != null) onSelected(filter);
        },
      ),
    );
  }
}
