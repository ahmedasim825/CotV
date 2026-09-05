import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/food_models.dart';
import '../../providers/nutrition_providers.dart';
import '../../providers/user_settings_providers.dart';
import '../components/components.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// Edits the four daily nutrition goals the dashboard is measured against.
Future<void> showNutritionTargetsSheet(BuildContext context) {
  return showStandardBottomSheet<void>(
    context,
    builder: (context) => const _NutritionTargetsSheet(),
  );
}

/// One editable goal. Kept as a table rather than four near-identical
/// blocks, so adding a fifth target is one row.
typedef _TargetField = ({
  String label,
  String unit,
  IconData icon,
  int Function(NutritionTargets) read,
});

const List<_TargetField> _fields = [
  (
    label: 'Calories',
    unit: 'kcal',
    icon: PhLight.fire,
    read: _calories,
  ),
  (
    label: 'Protein',
    unit: 'g',
    icon: PhLight.bowlFood,
    read: _protein,
  ),
  (
    label: 'Carbs',
    unit: 'g',
    icon: PhLight.bowlFood,
    read: _carbs,
  ),
  (
    label: 'Fat',
    unit: 'g',
    icon: PhLight.drop,
    read: _fat,
  ),
];

int _calories(NutritionTargets targets) => targets.calories;
int _protein(NutritionTargets targets) => targets.protein;
int _carbs(NutritionTargets targets) => targets.carbs;
int _fat(NutritionTargets targets) => targets.fat;

class _NutritionTargetsSheet extends ConsumerStatefulWidget {
  const _NutritionTargetsSheet();

  @override
  ConsumerState<_NutritionTargetsSheet> createState() =>
      _NutritionTargetsSheetState();
}

class _NutritionTargetsSheetState
    extends ConsumerState<_NutritionTargetsSheet> {
  late final List<TextEditingController> _controllers;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final targets = ref.read(nutritionTargetsProvider);
    _controllers = [
      for (final field in _fields)
        TextEditingController(text: field.read(targets).toString()),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Every field has to hold a positive number — a goal of zero would make
  /// the dashboard ring divide by nothing.
  bool get _isValid => _controllers.every((controller) {
        final value = int.tryParse(controller.text.trim());
        return value != null && value > 0;
      });

  int _valueAt(int index) => int.parse(_controllers[index].text.trim());

  void _resetToDefaults() {
    const defaults = NutritionTargets.defaults;
    setState(() {
      for (var i = 0; i < _fields.length; i++) {
        _controllers[i].text = _fields[i].read(defaults).toString();
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    await ref.read(userSettingsControllerProvider.notifier).setNutritionTargets(
          calories: _valueAt(0),
          protein: _valueAt(1),
          carbs: _valueAt(2),
          fat: _valueAt(3),
        );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return StandardBottomSheet(
      title: 'Daily targets',
      subtitle: 'What the Nutrition card on the dashboard measures the day '
          'against.',
      heightFactor: 0.75,
      trailing: Semantics(
        button: true,
        label: 'Reset to defaults',
        child: GestureDetector(
          onTap: _isSaving ? null : _resetToDefaults,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: minTouchTarget,
            height: minTouchTarget,
            child: Icon(
              PhLight.arrowClockwise,
              size: 18,
              color: palette.textMuted,
            ),
          ),
        ),
      ),
      actions: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Cancel',
              variant: ButtonVariant.outline,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: 'Save',
              icon: PhLight.check,
              expand: true,
              loading: _isSaving,
              onPressed: _isValid ? _save : null,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _fields.length; i++) ...[
            FieldLabel(icon: _fields[i].icon, label: _fields[i].label),
            const SizedBox(height: 10),
            TextField(
              controller: _controllers[i],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !_isSaving,
              onChanged: (_) => setState(() {}),
              decoration: appInputDecoration(
                context,
                hint: _fields[i]
                    .read(NutritionTargets.defaults)
                    .toString(),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    _fields[i].unit,
                    textAlign: TextAlign.right,
                    style: context.typography.ui(
                      size: 13,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
              style: context.typography.ui(size: 15),
            ),
            if (i < _fields.length - 1) const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
