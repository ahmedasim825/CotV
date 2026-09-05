import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/food_models.dart';
import '../../providers/nutrition_providers.dart';
import '../../services/nutritionix_service.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'food_detail_screen.dart';
import 'food_route.dart';
import 'recipe_builder_screen.dart';
import 'widgets/barcode_scanner_sheet.dart';
import 'widgets/food_search_field.dart';
import 'widgets/food_thumbnail.dart';
import 'widgets/macro_readout.dart';

/// The three ways into the logger.
enum FoodSource { search, scan, recipes }

extension _FoodSourceX on FoodSource {
  String get label {
    switch (this) {
      case FoodSource.search:
        return 'Search Database';
      case FoodSource.scan:
        return 'Scan Barcode';
      case FoodSource.recipes:
        return 'My Recipes';
    }
  }

  IconData get icon {
    switch (this) {
      case FoodSource.search:
        return PhLight.magnifyingGlass;
      case FoodSource.scan:
        return PhLight.barcode;
      case FoodSource.recipes:
        return PhLight.cookingPot;
    }
  }
}

/// The food logger's front door: search, scan or pick one of your own
/// recipes, then configure the portion.
///
/// Renders without a [Scaffold], like every other pane in this app, so the
/// same widget serves as the Food tab and as a pushed page (see
/// `pushFoodPage`).
class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key});

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  FoodSource _source = FoodSource.search;
  bool _isResolving = false;
  String? _error;

  /// Resolves a search hit to real nutrients, then opens the configurator.
  ///
  /// The instant endpoint returns no nutrients for a common food and only
  /// calories for a branded one, so this round trip is what makes a row
  /// loggable.
  Future<void> _openHit(FoodSearchHit hit) async {
    setState(() {
      _isResolving = true;
      _error = null;
    });

    try {
      final food =
          await ref.read(nutritionixServiceProvider).getFoodDetails(hit.name);
      if (!mounted) return;
      setState(() => _isResolving = false);
      await pushFoodPage(context, FoodDetailScreen(food: food));
    } on NutritionixException catch (error) {
      if (!mounted) return;
      setState(() {
        _isResolving = false;
        _error = error.message;
      });
    }
  }

  /// Swallows taps while a lookup is in flight, so a second tap cannot
  /// start a second request against the same rate limit.
  void _ignore(FoodSearchHit hit) {}

  Future<void> _scan() async {
    final food = await showBarcodeScannerSheet(context);
    if (food == null || !mounted) return;
    await pushFoodPage(context, FoodDetailScreen(food: food));
  }

  Future<void> _openRecipeBuilder({CustomRecipe? existing}) {
    return pushFoodPage(
      context,
      RecipeBuilderScreen(existing: existing),
    );
  }

  /// Logs one serving of [recipe] through the same configurator a database
  /// food goes through, so the portion and meal are chosen the same way.
  Future<void> _openRecipe(CustomRecipe recipe) {
    final perServing = recipe.perServing;

    return pushFoodPage(
      context,
      FoodDetailScreen(
        food: FoodItem(
          name: recipe.title,
          perServing: perServing,
          servingUnit: 'serving',
          // One serving weighs its share of the finished dish, which is
          // what lets the gram field work on a recipe too.
          servingWeightGrams: recipe.yieldServings > 0
              ? recipe.totalGrams / recipe.yieldServings
              : null,
          thumbUrl: recipe.coverImageUrl,
          highresUrl: recipe.coverImageUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final padding = windowSize.pagePadding;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            padding,
            8,
            padding,
            96 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const FoodBackButton(),
            const SizedBox(height: 8),
            const SectionHeader(eyebrow: 'NUTRITION', title: 'Log food'),
            const SizedBox(height: 20),
            _SourceTabs(
              selected: _source,
              onSelect: (source) => setState(() {
                _source = source;
                _error = null;
              }),
            ),
            const SizedBox(height: 22),
            if (_error != null) ...[
              StatusCard(message: _error!, tone: StatusTone.error),
              const SizedBox(height: 18),
            ],
            ..._body(),
          ],
        );
      },
    );
  }

  List<Widget> _body() {
    switch (_source) {
      case FoodSource.search:
        return [
          const FoodSearchField(),
          const SizedBox(height: 18),
          // The results stay mounted while a food is being resolved.
          // Replacing them would dispose the autoDispose search provider,
          // and remounting it on the way back would re-run the query — a
          // second billed request for every food opened.
          if (_isResolving) ...[
            const _Busy(message: 'Fetching nutrition…'),
            const SizedBox(height: 12),
          ],
          FoodSearchResults(onSelect: _isResolving ? _ignore : _openHit),
        ];
      case FoodSource.scan:
        return [_ScanPanel(onScan: _scan)];
      case FoodSource.recipes:
        return [
          _RecipeList(
            onOpen: _openRecipe,
            onEdit: (recipe) => _openRecipeBuilder(existing: recipe),
            onCreate: _openRecipeBuilder,
          ),
        ];
    }
  }
}

class _SourceTabs extends StatelessWidget {
  const _SourceTabs({required this.selected, required this.onSelect});

  final FoodSource selected;
  final ValueChanged<FoodSource> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across once each tab clears about 150pt; below that the
        // longest label ("Search Database") ellipsises to nothing useful.
        final horizontal = constraints.maxWidth >= 460;
        final tabs = [
          for (final source in FoodSource.values)
            _SourceTab(
              source: source,
              isSelected: source == selected,
              onTap: () => onSelect(source),
            ),
        ];

        if (!horizontal) {
          return Column(
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                SizedBox(width: double.infinity, child: tabs[i]),
                if (i < tabs.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              Expanded(child: tabs[i]),
              if (i < tabs.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}

class _SourceTab extends StatelessWidget {
  const _SourceTab({
    required this.source,
    required this.isSelected,
    required this.onTap,
  });

  final FoodSource source;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: source.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: AppMotion.spring,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isSelected ? palette.accentSoft : palette.glassFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? palette.accent : palette.glassBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                source.icon,
                size: 17,
                color: isSelected ? palette.accentBright : palette.textMuted,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  source.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: isSelected
                        ? palette.textPrimary
                        : palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanPanel extends StatelessWidget {
  const _ScanPanel({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
      child: Column(
        children: [
          Icon(PhLight.barcode, size: 34, color: palette.accent),
          const SizedBox(height: 18),
          Text(
            barcodeCameraSupported
                ? 'Point the camera at a package barcode and the food is '
                    'looked up for you.'
                : 'This platform has no camera scanner, so the sheet asks '
                    'for the barcode number instead.',
            textAlign: TextAlign.center,
            style: context.typography.ui(
              size: 13,
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: barcodeCameraSupported ? 'Open scanner' : 'Enter a barcode',
            icon: barcodeCameraSupported ? PhLight.camera : PhLight.barcode,
            onPressed: onScan,
          ),
        ],
      ),
    );
  }
}

class _RecipeList extends ConsumerWidget {
  const _RecipeList({
    required this.onOpen,
    required this.onEdit,
    required this.onCreate,
  });

  final ValueChanged<CustomRecipe> onOpen;
  final ValueChanged<CustomRecipe> onEdit;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final recipes = ref.watch(customRecipeListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recipes.isEmpty)
          CustomCard(
            padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
            child: Column(
              children: [
                Icon(PhLight.cookingPot, size: 30, color: palette.textMuted),
                const SizedBox(height: 16),
                Text(
                  'Build a recipe once and log it by the serving from then on.',
                  textAlign: TextAlign.center,
                  style: context.typography.ui(
                    size: 13,
                    color: palette.textMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else
          for (final recipe in recipes) ...[
            _RecipeCard(
              key: ValueKey(recipe.id),
              recipe: recipe,
              onTap: () => onOpen(recipe),
              onEdit: () => onEdit(recipe),
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'New recipe',
          icon: PhLight.plus,
          expand: true,
          onPressed: onCreate,
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
    required this.onEdit,
  });

  final CustomRecipe recipe;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      onTap: onTap,
      semanticLabel: '${recipe.title}, '
          '${recipe.perServing.calories.round()} kcal per serving',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FoodThumbnail(
                filePath: recipe.coverImagePath,
                url: recipe.coverImageUrl,
                icon: PhLight.cookingPot,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.ui(
                        size: 15,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${recipe.ingredients.length} ingredients · makes '
                      '${recipe.yieldServings}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.ui(
                        size: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Edit ${recipe.title}',
                child: GestureDetector(
                  onTap: onEdit,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: minTouchTarget,
                    height: minTouchTarget,
                    child: Icon(
                      PhLight.pencilSimple,
                      size: 17,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          MacroReadout(totals: recipe.perServing, caption: 'Per serving'),
        ],
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          CircularProgressIndicator(color: palette.accent, strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text(
            message,
            style: context.typography.ui(size: 13, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
