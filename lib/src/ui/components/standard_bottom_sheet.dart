import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Presents [builder] inside the app's standard sheet chrome.
///
/// [enableDrag] defaults to false because every sheet in this app is a
/// form: dragging one away mid-edit silently loses work, so a form sheet
/// should close only through its own Cancel/Save controls or the scrim.
/// Pass true for read-only sheets, where dragging is the natural dismissal.
Future<T?> showStandardBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool enableDrag = false,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.palette.scrim,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    builder: builder,
  );
}

/// The chrome every modal sheet shares: a grabber, a title block, a
/// scrollable body and an optional pinned action row.
///
/// It lifts itself above the keyboard, caps its own height so a long form
/// still shows the page behind it, and keeps the action row visible while
/// the body scrolls underneath — so Save never scrolls off the bottom of a
/// long form.
class StandardBottomSheet extends StatelessWidget {
  const StandardBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.trailing,
    this.heightFactor = 0.9,
  });

  final String title;
  final String? subtitle;

  /// The sheet's body. Scrolls when it outgrows the available height.
  final Widget child;

  /// Pinned below the body — typically a Cancel/Save row.
  final Widget? actions;

  /// A control on the title's row, e.g. a delete button when editing.
  final Widget? trailing;

  /// Share of the screen height the sheet may grow to.
  final double heightFactor;

  /// Horizontal gutter shared by the title, body and action rows.
  static const EdgeInsets _gutter = EdgeInsets.fromLTRB(24, 0, 24, 8);


  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      // Lifts the sheet above the keyboard as it opens.
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * heightFactor,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(top: BorderSide(color: palette.innerHighlight)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: context.typography.display(
                              size: 26,
                              weight: FontWeight.w500,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle!,
                              style: context.typography.ui(
                                size: 13,
                                color: palette.textMuted,
                                height: 1.45,
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
              const SizedBox(height: 22),
              Flexible(
                child: SingleChildScrollView(
                  padding: _gutter,
                  child: child,
                ),
              ),
              if (actions != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: actions,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The drag handle at the top of a sheet.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: context.palette.glassBorder,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
