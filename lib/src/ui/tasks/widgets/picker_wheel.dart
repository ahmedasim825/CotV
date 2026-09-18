import 'package:flutter/cupertino.dart';

import '../../theme/app_theme.dart';

/// One column of a [PickerWheel].
///
/// Carries no values, only a count and a way to label an index — which is what
/// lets the same control spell hours and minutes on one row of the task sheet
/// and months and years on another.
@immutable
class WheelColumn {
  const WheelColumn({
    required this.count,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final int count;

  /// The index the column rests on. Changing it from outside — a month
  /// stepper, say — scrolls the column to match.
  final int selected;

  final String Function(int index) label;
  final ValueChanged<int> onChanged;
}

/// The side-by-side scroll wheels the task sheet picks a time and a month with.
///
/// Two of these exist in the sheet and they are the same control, so it lives
/// here rather than twice inside it. The look is the design's rather than
/// Cupertino's: no magnifier, no grey selection lozenge, and a single 1px rule
/// above and below the resting row drawn once across every column — the wheels
/// read as one control, and a band that stopped at the gap between them would
/// say otherwise.
class PickerWheel extends StatefulWidget {
  const PickerWheel({super.key, required this.columns});

  final List<WheelColumn> columns;

  static const double itemExtent = 32;
  static const int visibleRows = 5;

  /// The wheel's total height. Public so a caller can reserve the same space
  /// before the wheel is built.
  static const double height = itemExtent * visibleRows;

  @override
  State<PickerWheel> createState() => _PickerWheelState();
}

class _PickerWheelState extends State<PickerWheel> {
  late List<FixedExtentScrollController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final column in widget.columns)
        FixedExtentScrollController(initialItem: column.selected),
    ];
  }

  @override
  void didUpdateWidget(PickerWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (var i = 0; i < widget.columns.length; i++) {
      if (i >= _controllers.length) continue;
      final controller = _controllers[i];
      final selected = widget.columns[i].selected;
      // Only when the value moved for a reason other than this wheel: driving
      // the controller back to where it already is would fight the finger
      // still on it.
      if (controller.hasClients && controller.selectedItem != selected) {
        controller.animateToItem(
          selected,
          duration: context.motion.fast,
          curve: AppMotion.spring,
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      height: PickerWheel.height,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < widget.columns.length; i++)
                Expanded(child: _column(widget.columns[i], _controllers[i])),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: PickerWheel.itemExtent,
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: palette.fieldDivider),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(WheelColumn column, FixedExtentScrollController controller) {
    final palette = context.palette;

    return CupertinoPicker.builder(
      scrollController: controller,
      itemExtent: PickerWheel.itemExtent,
      childCount: column.count,
      useMagnifier: false,
      squeeze: 1.1,
      diameterRatio: 1.6,
      backgroundColor: const Color(0x00000000),
      // Drawn once over every column instead — see the Stack above.
      selectionOverlay: null,
      onSelectedItemChanged: column.onChanged,
      itemBuilder: (context, index) {
        final isSelected = index == column.selected;
        return Center(
          child: Text(
            column.label(index),
            style: context.typography.display(
              size: isSelected ? 22 : 20,
              weight: isSelected ? FontWeight.w700 : FontWeight.w400,
              letterSpacing: 0,
              color: isSelected
                  ? palette.textPrimary
                  : palette.textPrimary.withValues(alpha: 0.35),
            ),
          ),
        );
      },
    );
  }
}
