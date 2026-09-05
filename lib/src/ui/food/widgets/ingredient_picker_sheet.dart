import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/food_models.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import '../../widgets/status_card.dart';
import 'food_search_field.dart';
import 'macro_readout.dart';

/// Adds one ingredient to a recipe, from the database or by hand.
///
/// Returns the finished ingredient, or null if the sheet was dismissed.
Future<RecipeIngredient?> showIngredientPickerSheet(BuildContext context) {
  return showStandardBottomSheet<RecipeIngredient>(
    context,
    builder: (context) => const _IngredientPickerSheet(),
  );
}

/// Which of the sheet's three faces is showing.
enum _Step {
  /// The database search.
  search,

  /// A food has been resolved; how much of it goes in?
  weigh,

  /// Nutrients typed in by hand, for a food the database does not have.
  manual,
}

class _IngredientPickerSheet extends ConsumerStatefulWidget {
  const _IngredientPickerSheet();

  @override
  ConsumerState<_IngredientPickerSheet> createState() =>
      _IngredientPickerSheetState();
}

class _IngredientPickerSheetState
    extends ConsumerState<_IngredientPickerSheet> {
  final TextEditingController _gramsController =
      TextEditingController(text: '100');
  final TextEditingController _nameController = TextEditingController();
  final Map<String, TextEditingController> _manualControllers = {
    for (final field in _manualFields) field.key: TextEditingController(),
  };

  static const List<({String key, String label, String unit})> _manualFields = [
    (key: 'calories', label: 'Calories', unit: 'kcal'),
    (key: 'protein', label: 'Protein', unit: 'g'),
    (key: 'carbs', label: 'Carbs', unit: 'g'),
    (key: 'fat', label: 'Fat', unit: 'g'),
    (key: 'sodium', label: 'Sodium', unit: 'mg'),
    (key: 'potassium', label: 'Potassium', unit: 'mg'),
  ];

  _Step _step = _Step.search;
  FoodItem? _resolved;
  String? _error;

  @override
  void dispose() {
    _gramsController.dispose();
    _nameController.dispose();
    for (final controller in _manualControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _grams => double.tryParse(_gramsController.text) ?? 0;

  /// No network call: a search hit already carries every nutrient.
  void _resolve(FoodSearchHit hit) {
    setState(() {
      _resolved = hit.item;
      _error = null;
      _step = _Step.weigh;
      // Seed with one serving where the database declares one, and 100 g
      // otherwise - which is the basis the numbers are quoted on.
      _gramsController.text = formatAmount(hit.item.servingGrams);
    });
  }

  void _saveResolved() {
    final food = _resolved;
    if (food == null || _grams <= 0) return;

    Navigator.of(context).pop(
      RecipeIngredient(
        id: const Uuid().v4(),
        name: food.name,
        grams: _grams,
        totals: food.totalsForGrams(_grams),
      ),
    );
  }

  void _saveManual() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _grams <= 0) return;

    double read(String key) =>
        double.tryParse(_manualControllers[key]!.text) ?? 0;

    Navigator.of(context).pop(
      RecipeIngredient(
        id: const Uuid().v4(),
        name: name,
        grams: _grams,
        // Typed by hand for the amount actually used, so unlike a database
        // food there is nothing to scale.
        totals: NutritionTotals(
          calories: read('calories'),
          protein: read('protein'),
          carbs: read('carbs'),
          fat: read('fat'),
          sodium: read('sodium'),
          potassium: read('potassium'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.search:
        return _searchSheet();
      case _Step.weigh:
        return _weighSheet();
      case _Step.manual:
        return _manualSheet();
    }
  }

  Widget _searchSheet() {
    return StandardBottomSheet(
      title: 'Add ingredient',
      subtitle: 'Search the database, or enter one by hand.',
      actions: PrimaryButton(
        label: 'Enter by hand',
        icon: PhLight.notePencil,
        variant: ButtonVariant.outline,
        expand: true,
        onPressed: () => setState(() => _step = _Step.manual),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FoodSearchField(),
          const SizedBox(height: 16),
          if (_error != null) ...[
            StatusCard(message: _error!, tone: StatusTone.error),
            const SizedBox(height: 16),
          ],
          FoodSearchResults(onSelect: _resolve),
        ],
      ),
    );
  }

  Widget _weighSheet() {
    final food = _resolved!;

    return StandardBottomSheet(
      title: food.name,
      subtitle: 'How much of it does the recipe use?',
      heightFactor: 0.75,
      actions: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Back',
              variant: ButtonVariant.outline,
              expand: true,
              onPressed: () => setState(() => _step = _Step.search),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: 'Add',
              icon: PhLight.plus,
              expand: true,
              onPressed: _grams > 0 ? _saveResolved : null,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GramsField(controller: _gramsController, onChanged: _refresh),
          const SizedBox(height: 24),
          MacroReadout(
            totals: food.totalsForGrams(_grams),
            caption: 'This much',
          ),
        ],
      ),
    );
  }

  Widget _manualSheet() {
    return StandardBottomSheet(
      title: 'By hand',
      subtitle: 'Enter the nutrients for the amount this recipe uses.',
      heightFactor: 0.85,
      actions: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Back',
              variant: ButtonVariant.outline,
              expand: true,
              onPressed: () => setState(() => _step = _Step.search),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: 'Add',
              icon: PhLight.plus,
              expand: true,
              onPressed: _canSaveManual ? _saveManual : null,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel(icon: PhLight.tag, label: 'Ingredient'),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _refresh(),
            decoration: appInputDecoration(context, hint: 'Olive oil'),
            style: context.typography.ui(size: 15),
          ),
          const SizedBox(height: 20),
          _GramsField(controller: _gramsController, onChanged: _refresh),
          const SizedBox(height: 20),
          for (final field in _manualFields) ...[
            _NutrientField(
              label: field.label,
              unit: field.unit,
              controller: _manualControllers[field.key]!,
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  bool get _canSaveManual =>
      _nameController.text.trim().isNotEmpty && _grams > 0;

  void _refresh() => setState(() {});
}

class _GramsField extends StatelessWidget {
  const _GramsField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel(icon: PhLight.target, label: 'Weight in grams'),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          onChanged: (_) => onChanged(),
          decoration: appInputDecoration(context, hint: '100'),
          style: context.typography.ui(size: 15),
        ),
      ],
    );
  }
}

class _NutrientField extends StatelessWidget {
  const _NutrientField({
    required this.label,
    required this.unit,
    required this.controller,
  });

  final String label;
  final String unit;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.typography.ui(size: 13.5),
          ),
        ),
        SizedBox(
          width: 118,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.right,
            decoration: appInputDecoration(
              context,
              hint: '0',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  unit,
                  textAlign: TextAlign.right,
                  style: context.typography.ui(
                    size: 12,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
            style: context.typography.ui(size: 14),
          ),
        ),
      ],
    );
  }
}
