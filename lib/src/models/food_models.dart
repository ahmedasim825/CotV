import 'user_settings.dart';

/// The six nutrients this app tracks, as one value.
///
/// Every scaling and aggregation in the food logger goes through this type
/// rather than six loose doubles, so "half a serving" and "a quarter of the
/// recipe" are written once and cannot drift apart between screens.
class NutritionTotals {
  const NutritionTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sodium,
    required this.potassium,
  });

  static const NutritionTotals zero = NutritionTotals(
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0,
    sodium: 0,
    potassium: 0,
  );

  /// Kilocalories.
  final double calories;

  /// Grams.
  final double protein;
  final double carbs;
  final double fat;

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
    );
  }

  /// Per-serving breakdown of a recipe. A yield of zero or less returns
  /// [zero] rather than infinity — the recipe builder leaves the field
  /// empty while it is being typed into.
  NutritionTotals dividedBy(int servings) =>
      servings <= 0 ? zero : scaled(1 / servings);
}

/// A food resolved to actual numbers, from either `/natural/nutrients` or
/// a barcode lookup.
class FoodItem {
  const FoodItem({
    required this.name,
    required this.perServing,
    this.brandName,
    this.servingQty = 1,
    this.servingUnit = 'serving',
    this.servingWeightGrams,
    this.thumbUrl,
    this.highresUrl,
    this.upc,
  });

  final String name;

  /// Null for a common (unbranded) food.
  final String? brandName;

  /// The nutrients of exactly one serving as the API defines it.
  final NutritionTotals perServing;

  final double servingQty;
  final String servingUnit;

  /// What one serving weighs. Null for foods the database has no weight
  /// for, which is what makes the gram field unusable for them.
  final double? servingWeightGrams;

  final String? thumbUrl;
  final String? highresUrl;
  final String? upc;

  bool get canWeigh => servingWeightGrams != null && servingWeightGrams! > 0;

  /// e.g. "1 cup · 240 g", or just "1 cup" when there is no weight.
  String get servingLabel {
    final quantity = formatAmount(servingQty);
    if (!canWeigh) return '$quantity $servingUnit';
    return '$quantity $servingUnit · ${formatAmount(servingWeightGrams!)} g';
  }

  NutritionTotals totalsForServings(double servings) =>
      perServing.scaled(servings);

  /// Scales by weight. Falls back to one serving when the food carries no
  /// weight, so a caller never has to branch on [canWeigh] to get a number.
  NutritionTotals totalsForGrams(double grams) {
    if (!canWeigh) return perServing;
    return perServing.scaled(grams / servingWeightGrams!);
  }

  /// How many servings [grams] works out to.
  double servingsForGrams(double grams) =>
      canWeigh ? grams / servingWeightGrams! : 1;

  /// What [servings] weighs.
  double? gramsForServings(double servings) =>
      canWeigh ? servingWeightGrams! * servings : null;
}

/// One row of `/search/instant`.
///
/// Deliberately thinner than [FoodItem]: the instant endpoint returns no
/// nutrients for common foods and only calories for branded ones, so a hit
/// has to be resolved into a [FoodItem] before it can be logged.
class FoodSearchHit {
  const FoodSearchHit({
    required this.name,
    required this.isBranded,
    this.brandName,
    this.thumbUrl,
    this.servingPreview,
    this.caloriesPreview,
    this.upc,
  });

  final String name;
  final bool isBranded;
  final String? brandName;
  final String? thumbUrl;

  /// e.g. "1 cup" — what the database considers one serving.
  final String? servingPreview;

  /// Branded hits carry calories; common hits do not.
  final double? caloriesPreview;

  final String? upc;
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
