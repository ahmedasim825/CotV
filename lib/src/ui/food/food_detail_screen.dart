import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/food_models.dart';
import '../../providers/nutrition_providers.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import 'food_route.dart';
import 'widgets/food_thumbnail.dart';
import 'widgets/macro_readout.dart';

/// How much one tap of the stepper moves the serving count.
const double _servingStep = 0.5;

/// The serving configurator: a resolved food, a portion, and the meal it
/// goes in.
///
/// Everything below the portion controls is derived — there is no second
/// copy of the numbers to keep in sync, so typing in the gram field and
/// tapping the stepper cannot disagree.
class FoodDetailScreen extends ConsumerStatefulWidget {
  const FoodDetailScreen({super.key, required this.food});

  final FoodItem food;

  @override
  ConsumerState<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends ConsumerState<FoodDetailScreen> {
  final TextEditingController _gramsController = TextEditingController();

  late MealSlot _meal = mealSlotForHour(DateTime.now().hour);
  double _servings = 1;

  /// Guards the two controls against each other: writing the gram field
  /// from the stepper fires its listener, which would otherwise recompute
  /// the serving count from the rounded gram text and drift.
  bool _syncing = false;

  FoodItem get _food => widget.food;

  NutritionTotals get _totals => _food.totalsForServings(_servings);

  @override
  void initState() {
    super.initState();
    _writeGrams();
    _gramsController.addListener(_onGramsChanged);
  }

  @override
  void dispose() {
    _gramsController.dispose();
    super.dispose();
  }

  void _writeGrams() {
    final grams = _food.gramsForServings(_servings);
    if (grams == null) return;
    _syncing = true;
    _gramsController.text = formatAmount(grams);
    _syncing = false;
  }

  void _onGramsChanged() {
    if (_syncing) return;
    final grams = double.tryParse(_gramsController.text);
    if (grams == null || grams <= 0) return;
    setState(() => _servings = _food.servingsForGrams(grams));
  }

  void _setServings(double value) {
    // A tenth of a serving is the smallest portion worth logging, and it
    // keeps the stepper from walking into 0.
    final next = value.clamp(0.1, 99.0).toDouble();
    setState(() => _servings = next);
    _writeGrams();
  }

  void _addToLog() {
    ref.read(dailyNutritionProvider.notifier).log(
          LoggedFood(
            id: const Uuid().v4(),
            name: _food.name,
            brandName: _food.brandName,
            meal: _meal,
            servings: _servings,
            grams: _food.gramsForServings(_servings),
            totals: _totals,
            loggedAt: DateTime.now(),
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AdaptiveLayout(
      builder: (context, windowSize) {
        final padding = windowSize.pagePadding;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            padding,
            8,
            padding,
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const FoodBackButton(),
            const SizedBox(height: 8),
            _Hero(food: _food),
            const SizedBox(height: 24),
            Text(
              _food.name,
              style: context.typography.display(size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (_food.brandName != null && _food.brandName!.isNotEmpty)
                  _food.brandName!,
                _food.servingLabel,
              ].join(' · '),
              style: context.typography.ui(size: 13, color: palette.textMuted),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              eyebrow: 'PORTION',
              title: 'How much?',
              titleSize: 20,
            ),
            const SizedBox(height: 16),
            _PortionControls(
              servings: _servings,
              gramsController: _gramsController,
              canWeigh: _food.canWeigh,
              onServingsChanged: _setServings,
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              eyebrow: 'MEAL',
              title: 'Where does it go?',
              titleSize: 20,
            ),
            const SizedBox(height: 16),
            _MealChips(
              selected: _meal,
              onSelect: (meal) => setState(() => _meal = meal),
            ),
            const SizedBox(height: 28),
            CustomCard(
              child: MacroReadout(
                totals: _totals,
                caption: 'This portion',
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Add to Meal Log',
              icon: PhLight.plus,
              expand: true,
              onPressed: _addToLog,
            ),
          ],
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.food});

  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: FoodThumbnail(
        url: food.highresUrl ?? food.thumbUrl,
        size: null,
        radius: 24,
      ),
    );
  }
}

/// The serving stepper and the gram field, which drive the same number.
class _PortionControls extends StatelessWidget {
  const _PortionControls({
    required this.servings,
    required this.gramsController,
    required this.canWeigh,
    required this.onServingsChanged,
  });

  final double servings;
  final TextEditingController gramsController;
  final bool canWeigh;
  final ValueChanged<double> onServingsChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel(icon: PhLight.bowlFood, label: 'Servings'),
        const SizedBox(height: 10),
        Row(
          children: [
            _StepperButton(
              icon: PhLight.minusCircle,
              semanticLabel: 'Fewer servings',
              onTap: () => onServingsChanged(servings - _servingStep),
            ),
            Expanded(
              child: Center(
                child: Text(
                  formatAmount(servings),
                  style: context.typography.display(size: 30),
                ),
              ),
            ),
            _StepperButton(
              icon: PhLight.plusCircle,
              semanticLabel: 'More servings',
              onTap: () => onServingsChanged(servings + _servingStep),
            ),
          ],
        ),
        const SizedBox(height: 22),
        FieldLabel(
          icon: PhLight.target,
          label: 'Weight',
          optional: !canWeigh,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: gramsController,
          enabled: canWeigh,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: appInputDecoration(
            context,
            // A food the database carries no serving weight for cannot be
            // logged by weight at all, so the field says why rather than
            // accepting a number it would have to ignore.
            hint: canWeigh ? '180' : 'No weight on record for this food',
            suffixIcon: canWeigh
                ? Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Text(
                      'g',
                      textAlign: TextAlign.right,
                      style: context.typography.ui(
                        size: 14,
                        color: palette.textMuted,
                      ),
                    ),
                  )
                : null,
          ),
          style: context.typography.ui(size: 15),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 56,
          height: minTouchTarget,
          child: Icon(icon, size: 30, color: palette.accent),
        ),
      ),
    );
  }
}

class _MealChips extends StatelessWidget {
  const _MealChips({required this.selected, required this.onSelect});

  final MealSlot selected;
  final ValueChanged<MealSlot> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final meal in MealSlot.values)
          _MealChip(
            meal: meal,
            isSelected: meal == selected,
            onTap: () => onSelect(meal),
          ),
      ],
    );
  }
}

class _MealChip extends StatelessWidget {
  const _MealChip({
    required this.meal,
    required this.isSelected,
    required this.onTap,
  });

  final MealSlot meal;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: meal.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: AppMotion.spring,
          constraints: const BoxConstraints(minHeight: minTouchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: isSelected ? palette.accentSoft : palette.glassFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected ? palette.accent : palette.glassBorder,
            ),
          ),
          child: Text(
            meal.label,
            style: context.typography.ui(
              size: 13.5,
              weight: FontWeight.w600,
              color: isSelected ? palette.textPrimary : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
