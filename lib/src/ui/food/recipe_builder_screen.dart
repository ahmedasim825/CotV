import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../models/food_models.dart';
import '../../providers/auth_providers.dart';
import '../../providers/nutrition_providers.dart';
import '../../services/nutrition_sync_service.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'food_route.dart';
import 'widgets/food_thumbnail.dart';
import 'widgets/ingredient_picker_sheet.dart';
import 'widgets/macro_readout.dart';

/// Builds a multi-ingredient recipe and works out what one serving of it
/// comes to.
///
/// The totals are never stored: [CustomRecipe] derives them from its
/// ingredients, so an edited weight cannot leave a stale number behind.
class RecipeBuilderScreen extends ConsumerStatefulWidget {
  const RecipeBuilderScreen({super.key, this.existing});

  /// Null when building a new recipe.
  final CustomRecipe? existing;

  @override
  ConsumerState<RecipeBuilderScreen> createState() =>
      _RecipeBuilderScreenState();
}

class _RecipeBuilderScreenState extends ConsumerState<RecipeBuilderScreen> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _yieldController = TextEditingController(
    text: (widget.existing?.yieldServings ?? 4).toString(),
  );
  late final TextEditingController _imageUrlController =
      TextEditingController(text: widget.existing?.coverImageUrl ?? '');

  late List<RecipeIngredient> _ingredients =
      List.of(widget.existing?.ingredients ?? const []);

  late String? _coverImagePath = widget.existing?.coverImagePath;

  /// True while a cover is going up, so Save can show a spinner rather
  /// than looking hung on a slow connection.
  bool _isUploadingCover = false;

  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _yieldController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  int get _yieldServings => int.tryParse(_yieldController.text) ?? 0;

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty &&
      _yieldServings >= 1 &&
      _ingredients.isNotEmpty;

  CustomRecipe get _draft => CustomRecipe(
        id: widget.existing?.id ?? const Uuid().v4(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        // Clamped so the per-serving card divides by something real while
        // the field is mid-edit or empty.
        yieldServings: _yieldServings < 1 ? 1 : _yieldServings,
        ingredients: _ingredients,
        coverImagePath: _coverImagePath,
        coverImageUrl: _imageUrlController.text.trim().isEmpty
            ? null
            : _imageUrlController.text.trim(),
      );

  Future<void> _addIngredient() async {
    final ingredient = await showIngredientPickerSheet(context);
    if (ingredient == null) return;
    setState(() => _ingredients = [..._ingredients, ingredient]);
  }

  void _removeIngredient(String id) {
    setState(() {
      _ingredients =
          _ingredients.where((ingredient) => ingredient.id != id).toList();
    });
  }

  Future<void> _pickCover() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      setState(() {
        _coverImagePath = picked.path;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      // A denied photo-library permission is the usual cause, and it
      // should not take the whole form down with it.
      setState(() => _error = error.message ?? 'Could not open the picker.');
    }
  }

  /// Saves the recipe, uploading a newly picked cover first.
  ///
  /// The upload happens before the save rather than after, so the row is
  /// written with the object path already in it and there is no window
  /// where a recipe points at a cover that is not there yet. A failed
  /// upload does not block the save: the recipe is worth more than its
  /// photo, so it is stored with the local path still set and the error
  /// shown.
  Future<void> _save() async {
    final sync = ref.read(nutritionSyncServiceProvider);
    final localCover = _coverImagePath;
    var recipe = _draft;

    if (sync != null && localCover != null) {
      setState(() => _isUploadingCover = true);
      try {
        final objectPath = await sync.uploadRecipeCover(
          recipeId: recipe.id,
          filePath: localCover,
        );
        recipe = recipe.copyWith(coverImageUrl: objectPath);
      } on NutritionSyncException catch (error) {
        if (mounted) setState(() => _error = error.message);
      } finally {
        if (mounted) setState(() => _isUploadingCover = false);
      }
    }

    await ref.read(customRecipeListProvider.notifier).save(recipe);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final recipe = _draft;

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
            SectionHeader(
              eyebrow: 'RECIPE',
              title: widget.existing == null ? 'New recipe' : 'Edit recipe',
            ),
            const SizedBox(height: 24),
            _CoverPhoto(
              filePath: _coverImagePath,
              url: _imageUrlController.text.trim(),
              onPick: _pickCover,
              onClear: _coverImagePath == null
                  ? null
                  : () => setState(() => _coverImagePath = null),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _imageUrlController,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: appInputDecoration(
                context,
                hint: '…or paste an image URL',
                prefixIcon:
                    Icon(PhLight.link, size: 16, color: palette.textMuted),
              ),
              style: context.typography.ui(size: 14),
            ),
            const SizedBox(height: 24),
            const FieldLabel(icon: PhLight.notePencil, label: 'Title'),
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration:
                  appInputDecoration(context, hint: 'Chicken and rice bowl'),
              style: context.typography.ui(size: 15),
            ),
            const SizedBox(height: 20),
            const FieldLabel(
              icon: PhLight.textAlignLeft,
              label: 'Description',
              optional: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: appInputDecoration(
                context,
                hint: 'What is in it, and how it is made.',
              ),
              style: context.typography.ui(size: 14, height: 1.45),
            ),
            const SizedBox(height: 20),
            const FieldLabel(icon: PhLight.bowlFood, label: 'Makes'),
            const SizedBox(height: 10),
            TextField(
              controller: _yieldController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: appInputDecoration(
                context,
                hint: '4',
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    'servings',
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
            const SizedBox(height: 32),
            SectionHeader(
              eyebrow: 'INGREDIENTS',
              title: _ingredients.isEmpty
                  ? 'Nothing yet'
                  : '${_ingredients.length} in this recipe',
              titleSize: 20,
              trailing: PrimaryButton(
                label: 'Add',
                icon: PhLight.plus,
                size: ButtonSize.compact,
                onPressed: _addIngredient,
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              StatusCard(message: _error!, tone: StatusTone.error),
              const SizedBox(height: 16),
            ],
            if (_ingredients.isEmpty)
              _EmptyIngredients(onAdd: _addIngredient)
            else
              for (final ingredient in _ingredients) ...[
                _IngredientRow(
                  key: ValueKey(ingredient.id),
                  ingredient: ingredient,
                  onRemove: () => _removeIngredient(ingredient.id),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 28),
            _TotalsCard(recipe: recipe),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Save recipe',
              icon: PhLight.floppyDisk,
              expand: true,
              loading: _isUploadingCover,
              onPressed: _canSave && !_isUploadingCover ? _save : null,
            ),
            if (!_canSave) ...[
              const SizedBox(height: 12),
              Text(
                'A recipe needs a title, at least one ingredient, and a '
                'yield of one serving or more.',
                textAlign: TextAlign.center,
                style: context.typography.ui(
                  size: 12,
                  color: palette.textMuted,
                  height: 1.45,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The cover image, and the control that picks one.
class _CoverPhoto extends StatelessWidget {
  const _CoverPhoto({
    required this.filePath,
    required this.url,
    required this.onPick,
    this.onClear,
  });

  final String? filePath;
  final String url;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  bool get _hasImage => (filePath != null && filePath!.isNotEmpty) ||
      url.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _hasImage
              ? FoodThumbnail(
                  filePath: filePath,
                  url: url.isEmpty ? null : url,
                  size: null,
                  radius: 22,
                  icon: PhLight.imageSquare,
                )
              : DottedPlate(onTap: onPick),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: _hasImage ? 'Choose another' : 'Choose a photo',
                icon: PhLight.imageSquare,
                variant: ButtonVariant.outline,
                size: ButtonSize.compact,
                expand: true,
                onPressed: onPick,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Remove cover photo',
                child: GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: minTouchTarget,
                    height: minTouchTarget,
                    child: Icon(PhLight.trash, size: 18, color: palette.danger),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The empty cover slot.
class DottedPlate extends StatelessWidget {
  const DottedPlate({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      label: 'Choose a cover photo',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: palette.glassFill,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.glassBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhLight.imageSquare, size: 26, color: palette.textMuted),
              const SizedBox(height: 10),
              Text(
                'Add a cover photo',
                style:
                    context.typography.ui(size: 13, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    super.key,
    required this.ingredient,
    required this.onRemove,
  });

  final RecipeIngredient ingredient;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final totals = ingredient.totals;

    return CustomCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      radius: 18,
      elevated: false,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingredient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.typography.ui(size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatAmount(ingredient.grams)} g · '
                  '${totals.calories.round()} kcal · '
                  'P ${totals.protein.toStringAsFixed(1)} · '
                  'C ${totals.carbs.toStringAsFixed(1)} · '
                  'F ${totals.fat.toStringAsFixed(1)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 11.5,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Remove ${ingredient.name}',
            child: GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: minTouchTarget,
                height: minTouchTarget,
                child: Icon(PhLight.minusCircle, size: 20, color: palette.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyIngredients extends StatelessWidget {
  const _EmptyIngredients({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      onTap: onAdd,
      semanticLabel: 'Add the first ingredient',
      child: Column(
        children: [
          Icon(PhLight.cookingPot, size: 28, color: palette.textMuted),
          const SizedBox(height: 14),
          Text(
            'Add ingredients and their weights — the totals and the '
            'per-serving breakdown work themselves out.',
            textAlign: TextAlign.center,
            style: context.typography.ui(
              size: 13,
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole recipe against one serving of it.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.recipe});

  final CustomRecipe recipe;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      tint: palette.heroTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MacroReadout(
            totals: recipe.perServing,
            caption: 'Per serving',
          ),
          const SizedBox(height: 22),
          Divider(height: 1, thickness: 1, color: palette.hairline),
          const SizedBox(height: 22),
          MacroReadout(
            totals: recipe.total,
            caption: 'Whole recipe · '
                '${formatAmount(recipe.totalGrams)} g · '
                'makes ${recipe.yieldServings}',
            accent: palette.secondary,
          ),
        ],
      ),
    );
  }
}
