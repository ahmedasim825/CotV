import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';

import '../../platform/sf_symbols.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// One entry in a [PillDropdown].
@immutable
class PillOption<T> {
  const PillOption({
    required this.value,
    required this.label,
    this.color,
    this.leading,
    this.symbol,
    this.dividerAfter = false,
    this.inert = false,
  });

  final T value;
  final String label;

  /// Tints the default dot, and the [symbol] in the native menu. Null draws no
  /// dot — the entry is named and nothing more.
  final Color? color;

  /// Drawn ahead of the label in place of the dot, in the trigger and in the
  /// hand-rolled menu. The priority rows pass their exclamation marks here.
  ///
  /// The native menu cannot take it: [CNPopupMenuItem] accepts an icon and not
  /// a widget, which is what [symbol] is for.
  final Widget? leading;

  /// The SF Symbol the native menu marks this entry with. Defaults to a filled
  /// circle when [color] is set and this is not.
  final String? symbol;

  /// Draws a rule under this entry in the menu — the groups the design splits.
  final bool dividerAfter;

  /// Renders, and selecting it changes nothing.
  ///
  /// `Custom` in the repeat and early-reminder menus, which is on screen before
  /// the picker behind it has been designed — deliberately visible and
  /// deliberately doing nothing, the way the ⓘ was before this sheet existed.
  final bool inert;
}

/// The task sheet's `● Label ⌄` control, used for Subject, Priority, Repeat and
/// Early Reminder.
///
/// The label is always plain white and the colour is carried by the dot or the
/// marks beside it: a name tinted to match its own swatch reads as two
/// statements of the same thing, and at Low's grey it reads as disabled.
///
/// ## Two menus
///
/// On iOS 26 this is [CNPopupMenuButton] — a native `UIMenu` — sitting inside a
/// pill we draw, because the button draws its own trigger and takes no child.
/// (`CNPopupGesture`, the one control in the package that takes a child, opens
/// on long press through a plain Flutter dialog, which is neither the gesture
/// nor the menu this wants.) UIKit sets the entry icons at the trailing edge,
/// which is where the design draws them.
///
/// Everywhere else the package's fallback drops `tint`, dividers and every icon
/// on the floor, and all three carry meaning here — so off Apple platforms the
/// menu is hand-rolled instead, the way [NativeSwitch] hand-rolls its own
/// rather than accepting a bare Material switch. `TaskFilterMenu` takes the
/// package's fallback because it has only labels to lose.
///
/// Gated on [hasSFSymbols] for the reason documented there: the package picks
/// its path from `Platform.isIOS`, so a gate reading the faked theme would
/// disagree with it under `flutter_test` and in the Windows preview.
class PillDropdown<T> extends StatelessWidget {
  const PillDropdown({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.semanticLabel,
    this.menuTitle,
  });

  final List<PillOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// What a screen reader calls the control, e.g. `Priority`.
  final String semanticLabel;

  /// The heading over the hand-rolled sheet. Defaults to [semanticLabel].
  final String? menuTitle;

  static const double _radius = 8;
  static const double _dot = 10;

  /// The square the caret is centred in, at the trailing end of the pill.
  static const double _caretBox = 30;

  /// The chosen entry. Inert ones are skipped: `Custom` may share a value with
  /// whatever is currently set, and it must never be what the pill reads back.
  PillOption<T>? get _current {
    for (final option in options) {
      if (!option.inert && option.value == selected) return option;
    }
    return null;
  }

  void _report(int index) {
    if (index < 0 || index >= options.length) return;
    final option = options[index];
    if (option.inert) return;
    onSelected(option.value);
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;

    return Semantics(
      button: true,
      label: '$semanticLabel: ${current?.label ?? ''}',
      child: hasSFSymbols
          ? _native(context, current)
          : _fallback(context, current),
    );
  }

  /// The mark ahead of an entry's label: whatever [PillOption.leading] says, or
  /// a dot in its colour, or nothing.
  Widget? _mark(PillOption<T>? option) {
    if (option == null) return null;
    if (option.leading != null) return option.leading;
    final color = option.color;
    if (color == null) return null;
    return Container(
      width: _dot,
      height: _dot,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  /// The pill's chrome, shared by both paths so they cannot drift apart.
  Widget _pill(BuildContext context, PillOption<T>? current, Widget label) {
    final mark = _mark(current);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.pillFill,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mark != null) ...[const SizedBox(width: 12), mark],
          label,
          _caret(context),
        ],
      ),
    );
  }

  /// The same Phosphor glyph the calendar header uses, held back to 60% so it
  /// reads as an affordance rather than as a second label.
  ///
  /// Centred in a square of its own rather than dropped straight into the row:
  /// as a bare [Icon] it sat tight against the label on one side and against
  /// the pill's edge on the other, which read as crowded rather than as a
  /// control.
  Widget _caret(BuildContext context) {
    return SizedBox(
      width: _caretBox,
      height: _caretBox,
      child: Center(
        child: Icon(
          PhLight.caretDown,
          size: 12,
          color: context.palette.textPrimary.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _native(BuildContext context, PillOption<T>? current) {
    // A divider occupies a position in `items` on the package's own path, so
    // the entries and the dividers are built into one list and the index the
    // menu reports is mapped back through it.
    final entries = <CNPopupMenuEntry>[];
    final at = <int>[];

    for (var i = 0; i < options.length; i++) {
      final option = options[i];
      entries.add(
        CNPopupMenuItem(
          label: option.label,
          checked: !option.inert && option.value == selected,
          icon: option.symbol != null
              ? CNSymbol(option.symbol!, size: 14)
              : (option.color == null
                    ? null
                    : const CNSymbol('circle.fill', size: 12)),
          iconColor: option.color,
        ),
      );
      at.add(i);

      if (option.dividerAfter) {
        entries.add(const CNPopupMenuDivider());
        at.add(-1);
      }
    }

    return _pill(
      context,
      current,
      CNPopupMenuButton(
        buttonLabel: current?.label ?? '',
        tint: context.palette.textPrimary,
        buttonStyle: CNButtonStyle.plain,
        shrinkWrap: true,
        height: 30,
        items: entries,
        onSelected: (index) {
          if (index < 0 || index >= at.length) return;
          _report(at[index]);
        },
      ),
    );
  }

  Widget _fallback(BuildContext context, PillOption<T>? current) {
    return GestureDetector(
      onTap: () => _pick(context),
      // The whole pill takes the tap here, mark and caret included — which the
      // native path cannot manage, because its trigger is a platform view that
      // ends where the label does.
      behavior: HitTestBehavior.opaque,
      child: _pill(
        context,
        current,
        Padding(
          padding: EdgeInsets.fromLTRB(
            _mark(current) == null ? 12 : 8,
            6,
            0,
            6,
          ),
          child: Text(
            current?.label ?? '',
            style: context.typography.ui(size: 15, weight: FontWeight.w400),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showCupertinoModalPopup<int>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(
          menuTitle ?? semanticLabel,
          style: context.typography.ui(
            size: 13,
            color: context.palette.textMuted,
          ),
        ),
        // Built against the sheet's own context so `pop` reaches the popup
        // route rather than whatever sits under it.
        actions: [
          for (var i = 0; i < options.length; i++) ...[
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(i),
              child: _entry(context, options[i]),
            ),
            if (options[i].dividerAfter)
              Container(height: 1, color: context.palette.fieldDivider),
          ],
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(
            'Cancel',
            style: context.typography.ui(
              size: 17,
              weight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
        ),
      ),
    );

    if (picked == null) return;
    _report(picked);
  }

  /// One row of the hand-rolled menu.
  ///
  /// Every entry reads the same weight, the chosen one included: the pill
  /// directly above the menu already names the current value, so marking it
  /// again in the list is a second answer to a question nobody asked twice.
  Widget _entry(BuildContext context, PillOption<T> option) {
    final mark = _mark(option);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          option.label,
          style: context.typography.ui(
            size: 17,
            weight: FontWeight.w400,
            // Set, not inherited: a [CupertinoActionSheetAction] defaults its
            // label to the theme's primary colour, which on this palette is
            // the accent purple, and the design draws these plain.
            color: context.palette.textPrimary,
          ),
        ),
        if (mark != null) ...[const SizedBox(width: 10), mark],
      ],
    );
  }
}
