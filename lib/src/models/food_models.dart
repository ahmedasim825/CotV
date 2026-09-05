import 'user_settings.dart';

/// The seven nutrients this app tracks, as one value.
///
/// Every scaling and aggregation in the food logger goes through this type
/// rather than seven loose doubles, so "half a serving" and "a quarter of
/// the recipe" are written once and cannot drift apart between screens.
class NutritionTotals {
  const NutritionTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sodium,
    required this.potassium,
    // Defaulted rather than required: several databases omit fiber for
    // a given food, and the sync layer wrote six columns before this
    // existed. A required seventh would break both.
    this.fiber = 0,
  });

  static const NutritionTotals zero = NutritionTotals(
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0,
    sodium: 0,
    potassium: 0,
    fiber: 0,
  );

  /// Kilocalories.
  final double calories;

  /// Grams.
  final double protein;
  final double carbs;
  final double fat;

  /// Grams. Zero also means "this database had no value for it", which
  /// is why nothing reads a zero here as a measured absence.
  final double fiber;

  /// Milligrams.
  final double sodium;
  final double potassium;

  NutritionTotals operator +(NutritionTotals other) {
    return NutritionTotals(
      calories: calories + other.calories,
      protein: protein + other.protein,
      carbs: carbs + other.carbs,
      fat: fat + other.fat,
      sodium: sodium + other.sodium,
      potassium: potassium + other.potassium,
      fiber: fiber + other.fiber,
    );
  }

  NutritionTotals scaled(double factor) {
    return NutritionTotals(
      calories: calories * factor,
      protein: protein * factor,
      carbs: carbs * factor,
      fat: fat * factor,
      sodium: sodium * factor,
      potassium: potassium * factor,
      fiber: fiber * factor,
    );
  }

  /// Per-serving breakdown of a recipe. A yield of zero or less returns
  /// [zero] rather than infinity — the recipe builder leaves the field
  /// empty while it is being typed into.
  NutritionTotals dividedBy(int servings) =>
      servings <= 0 ? zero : scaled(1 / servings);
}

/// Which database a food came from.
enum FoodDataSource { usda, openFoodFacts }

extension FoodDataSourceX on FoodDataSource {
  /// Shown on a result row, so it is clear which database answered.
  String get label {
    switch (this) {
      case FoodDataSource.usda:
        return 'USDA';
      case FoodDataSource.openFoodFacts:
        return 'Open Food Facts';
    }
  }
}

/// A food resolved to actual numbers.
///
/// Nutrients are held **per 100 g**, because that is the basis both
/// backing databases quote: USDA returns per-100 g values for every data
/// type, and Open Food Facts' `*_100g` fields are the only ones a product
/// reliably has. Storing anything else would mean inventing a serving for
/// the many foods that declare none.
class FoodItem {
  const FoodItem({
    required this.name,
    required this.per100g,
    required this.source,
    this.brandName,
    this.servingWeightGrams,
    this.servingText,
    this.thumbUrl,
    this.highresUrl,
    this.barcode,
  });

  final String name;

  /// Null for a generic (unbranded) food.
  final String? brandName;

  /// The nutrients of exactly 100 g of this food.
  final NutritionTotals per100g;

  final FoodDataSource source;

  /// What the database says one serving weighs, when it says anything.
  /// Null for every USDA Foundation and SR Legacy food, and for OFF
  /// products with no `serving_quantity`.
  final double? servingWeightGrams;

  /// The database's own description of a serving, e.g. "1 portion (330 ml)".
  final String? servingText;

  final String? thumbUrl;
  final String? highresUrl;
  final String? barcode;

  bool get hasDeclaredServing =>
      servingWeightGrams != null && servingWeightGrams! > 0;

  /// What one "serving" means in grams.
  ///
  /// Falls back to 100 g rather than null, so the configurator's gram
  /// field is live for every food instead of being disabled for the
  /// generic ones - which are exactly the foods a user is most likely to
  /// want to weigh out.
  double get servingGrams => hasDeclaredServing ? servingWeightGrams! : 100;

  /// The line under the title saying what the numbers are quoted on.
  String get basisLabel {
    if (!hasDeclaredServing) return 'Per 100 g';
    if (servingText != null && servingText!.isNotEmpty) {
      return '$servingText · ${formatAmount(servingGrams)} g';
    }
    return '1 serving · ${formatAmount(servingGrams)} g';
  }

  NutritionTotals totalsForGrams(double grams) => per100g.scaled(grams / 100);

  NutritionTotals totalsForServings(double servings) =>
      totalsForGrams(servingGrams * servings);

  double servingsForGrams(double grams) => grams / servingGrams;

  double gramsForServings(double servings) => servingGrams * servings;
}

/// One row of the search results.
///
/// Carries the fully resolved [FoodItem]: USDA's search endpoint returns
/// every nutrient inline, so unlike the two-step flow this replaced there
/// is nothing left to fetch when a row is tapped.
class FoodSearchHit {
  const FoodSearchHit({
    required this.item,
    this.isBranded = false,
    this.sortRank = 0,
  });

  final FoodItem item;

  /// Whether this is a packaged product rather than a generic ingredient.
  /// Display only - ordering goes through [sortRank].
  final bool isBranded;

  /// Where this entry sorts, lowest first. Set from the USDA data type:
  /// whole-food records outrank survey composites, which outrank branded
  /// packages. See `FoodApiService.searchFoods`.
  final int sortRank;

  String get name => item.name;
  String? get brandName => item.brandName;
  String? get thumbUrl => item.thumbUrl;
  FoodDataSource get source => item.source;

  /// Calories per 100 g, which is what the row previews.
  double get caloriesPer100g => item.per100g.calories;
}

/// Which meal a logged food belongs to.
enum MealSlot { breakfast, lunch, dinner, snack }

extension MealSlotX on MealSlot {
  String get label {
    switch (this) {
      case MealSlot.breakfast:
        return 'Breakfast';
      case MealSlot.lunch:
        return 'Lunch';
      case MealSlot.dinner:
        return 'Dinner';
      case MealSlot.snack:
        return 'Snack';
    }
  }
}

/// The slot a food logged at [hour] most likely belongs to. Used to
/// preselect the meal chip, so the common case is zero taps.
MealSlot mealSlotForHour(int hour) {
  if (hour < 11) return MealSlot.breakfast;
  if (hour < 16) return MealSlot.lunch;
  if (hour < 21) return MealSlot.dinner;
  return MealSlot.snack;
}

/// A food as it sits in today's log, with its portion already applied.
///
/// [totals] is stored rather than recomputed, so an entry keeps the numbers
/// it was logged with even if the same food later resolves differently.
class LoggedFood {
  const LoggedFood({
    required this.id,
    required this.name,
    required this.meal,
    required this.servings,
    required this.totals,
    required this.loggedAt,
    this.brandName,
    this.grams,
  });

  final String id;
  final String name;
  final String? brandName;
  final MealSlot meal;
  final double servings;

  /// Null for a food with no serving weight.
  final double? grams;

  final NutritionTotals totals;
  final DateTime loggedAt;

  /// e.g. "1.5 servings · 240 g".
  String get portionLabel {
    final serving =
        '${formatAmount(servings)} ${servings == 1 ? 'serving' : 'servings'}';
    if (grams == null) return serving;
    return '$serving · ${formatAmount(grams!)} g';
  }
}

/// One line of a [CustomRecipe].
class RecipeIngredient {
  const RecipeIngredient({
    required this.id,
    required this.name,
    required this.grams,
    required this.totals,
  });

  final String id;
  final String name;

  /// How much of this ingredient the recipe uses.
  final double grams;

  /// The nutrients of exactly [grams] of it.
  final NutritionTotals totals;
}

/// A multi-ingredient recipe the user built themselves.
class CustomRecipe {
  const CustomRecipe({
    required this.id,
    required this.title,
    required this.yieldServings,
    required this.ingredients,
    this.description,
    this.coverImagePath,
    this.coverImageUrl,
  });

  final String id;
  final String title;
  final String? description;

  /// "Makes N servings". Never below 1 — the builder's form enforces it.
  final int yieldServings;

  final List<RecipeIngredient> ingredients;

  /// A file on this device, chosen with the image picker. Kept separate
  /// from [coverImageUrl] so a Storage upload later fills the remote one
  /// without this model changing shape.
  final String? coverImagePath;

  final String? coverImageUrl;

  /// The whole recipe.
  NutritionTotals get total => ingredients.fold(
        NutritionTotals.zero,
        (sum, ingredient) => sum + ingredient.totals,
      );

  /// What one serving of it works out to.
  NutritionTotals get perServing => total.dividedBy(yieldServings);

  double get totalGrams =>
      ingredients.fold(0, (sum, ingredient) => sum + ingredient.grams);

  CustomRecipe copyWith({
    String? title,
    String? description,
    int? yieldServings,
    List<RecipeIngredient>? ingredients,
    String? coverImagePath,
    String? coverImageUrl,
  }) {
    return CustomRecipe(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      yieldServings: yieldServings ?? this.yieldServings,
      ingredients: ingredients ?? this.ingredients,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
    );
  }
}

/// The daily goals the dashboard ring and macro bars are measured against.
class NutritionTargets {
  const NutritionTargets({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  /// What an unconfigured account is measured against.
  static const NutritionTargets defaults = NutritionTargets(
    calories: 2000,
    protein: 150,
    carbs: 220,
    fat: 70,
  );

  /// Resolves the persisted goals, falling back **per field**: someone who
  /// has set only a calorie goal keeps the default macro splits rather than
  /// losing all four to one unset value.
  ///
  /// A stored value of zero or less falls back too. Every target is a
  /// divisor on the dashboard, so a zero would put a NaN through the
  /// calorie ring rather than showing an empty one.
  factory NutritionTargets.fromSettings(UserSettings settings) {
    int resolve(int? stored, int fallback) =>
        stored != null && stored > 0 ? stored : fallback;

    return NutritionTargets(
      calories: resolve(settings.dailyCalorieTarget, defaults.calories),
      protein: resolve(settings.proteinTargetGrams, defaults.protein),
      carbs: resolve(settings.carbTargetGrams, defaults.carbs),
      fat: resolve(settings.fatTargetGrams, defaults.fat),
    );
  }

  /// Kilocalories.
  final int calories;

  /// Grams.
  final int protein;
  final int carbs;
  final int fat;
}

/// Renders a double without a trailing `.0`, so "1 serving" does not read
/// as "1.0 servings" and "240 g" does not read as "240.0 g".
String formatAmount(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(1);
}
