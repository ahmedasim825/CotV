import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/food_models.dart';

/// Anything the sync backend refused, already phrased for a StatusCard.
class NutritionSyncException implements Exception {
  const NutritionSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and writes the meal log, recipes and daily targets against
/// Supabase.
///
/// Every method assumes a signed-in user and passes `user_id` explicitly.
/// That is belt and braces: row-level security would reject a mismatched
/// id anyway, but sending it means the failure is a clear error rather
/// than a silently empty result.
class NutritionSyncService {
  NutritionSyncService(this._client);

  static const String coversBucket = 'recipe-covers';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const NutritionSyncException('Sign in to sync your food log.');
    }
    return id;
  }

  // ---------------------------------------------------------------------
  // Meal log
  // ---------------------------------------------------------------------

  /// Everything logged on [day], oldest first.
  Future<List<LoggedFood>> fetchLog(DateTime day) async {
    final rows = await _guard(
      () => _client
          .from('logged_foods')
          .select()
          .eq('user_id', _userId)
          .eq('logged_on', _dateOnly(day))
          .order('logged_at'),
      'Could not load your food log.',
    );

    return rows.map(_loggedFoodFrom).toList();
  }

  Future<void> insertLoggedFood(LoggedFood food, DateTime day) async {
    await _guard(
      () => _client.from('logged_foods').insert({
        'id': food.id,
        'user_id': _userId,
        'name': food.name,
        'brand_name': food.brandName,
        'meal': food.meal.name,
        'servings': food.servings,
        'grams': food.grams,
        'calories': food.totals.calories,
        'protein_grams': food.totals.protein,
        'carbs_grams': food.totals.carbs,
        'fat_grams': food.totals.fat,
        'sodium_mg': food.totals.sodium,
        'potassium_mg': food.totals.potassium,
        'logged_at': food.loggedAt.toUtc().toIso8601String(),
        // The user's local day, not a UTC one — a 23:30 snack belongs to
        // the day they ate it, which is the whole reason this column is
        // client-supplied.
        'logged_on': _dateOnly(day),
      }),
      'Could not save that food.',
    );
  }

  Future<void> deleteLoggedFood(String id) async {
    await _guard(
      () => _client.from('logged_foods').delete().eq('id', id),
      'Could not remove that entry.',
    );
  }

  // ---------------------------------------------------------------------
  // Recipes
  // ---------------------------------------------------------------------

  Future<List<CustomRecipe>> fetchRecipes() async {
    // One round trip for both levels: the nested select returns each
    // recipe with its ingredients attached, rather than N+1 queries.
    final rows = await _guard(
      () => _client
          .from('recipes')
          .select('*, recipe_ingredients(*)')
          .eq('user_id', _userId)
          .order('created_at', ascending: false),
      'Could not load your recipes.',
    );

    return rows.map(_recipeFrom).toList();
  }

  /// Writes [recipe] and replaces its ingredient rows.
  ///
  /// The ingredients are deleted and re-inserted rather than diffed: the
  /// builder hands over the whole list every save, reordering is a normal
  /// edit, and a recipe holds a handful of rows. Diffing would be more
  /// code for no user-visible difference.
  Future<void> saveRecipe(CustomRecipe recipe) async {
    await _guard(
      () => _client.from('recipes').upsert({
        'id': recipe.id,
        'user_id': _userId,
        'title': recipe.title,
        'description': recipe.description,
        'yield_servings': recipe.yieldServings,
        'cover_image_path': recipe.coverImageUrl,
      }),
      'Could not save the recipe.',
    );

    await _guard(
      () => _client
          .from('recipe_ingredients')
          .delete()
          .eq('recipe_id', recipe.id),
      'Could not update the recipe ingredients.',
    );

    if (recipe.ingredients.isEmpty) return;

    await _guard(
      () => _client.from('recipe_ingredients').insert([
        for (var i = 0; i < recipe.ingredients.length; i++)
          {
            'recipe_id': recipe.id,
            'position': i,
            'name': recipe.ingredients[i].name,
            'grams': recipe.ingredients[i].grams,
            'calories': recipe.ingredients[i].totals.calories,
            'protein_grams': recipe.ingredients[i].totals.protein,
            'carbs_grams': recipe.ingredients[i].totals.carbs,
            'fat_grams': recipe.ingredients[i].totals.fat,
            'sodium_mg': recipe.ingredients[i].totals.sodium,
            'potassium_mg': recipe.ingredients[i].totals.potassium,
          },
      ]),
      'Could not save the recipe ingredients.',
    );
  }

  Future<void> deleteRecipe(String id) async {
    // The ingredients go with it: the foreign key cascades.
    await _guard(
      () => _client.from('recipes').delete().eq('id', id),
      'Could not delete the recipe.',
    );
  }

  // ---------------------------------------------------------------------
  // Cover photos
  // ---------------------------------------------------------------------

  /// Uploads a local cover photo and returns its object path.
  ///
  /// The path leads with the user's id because the storage policies check
  /// exactly that segment — an object anywhere else is rejected.
  Future<String> uploadRecipeCover({
    required String recipeId,
    required String filePath,
  }) async {
    final extension = filePath.contains('.')
        ? filePath.split('.').last.toLowerCase()
        : 'jpg';
    final objectPath = '$_userId/$recipeId.$extension';

    await _guard(
      () => _client.storage.from(coversBucket).upload(
            objectPath,
            File(filePath),
            fileOptions: const FileOptions(upsert: true),
          ),
      'Could not upload the cover photo.',
    );

    return objectPath;
  }

  /// A temporary URL for a cover. The bucket is private, so there is no
  /// permanent public link to store.
  Future<String> signedCoverUrl(String objectPath) {
    return _guard(
      () => _client.storage.from(coversBucket).createSignedUrl(
            objectPath,
            const Duration(hours: 1).inSeconds,
          ),
      'Could not open the cover photo.',
    );
  }

  // ---------------------------------------------------------------------
  // Daily targets
  // ---------------------------------------------------------------------

  Future<NutritionTargets?> fetchTargets() async {
    final row = await _guard(
      () => _client
          .from('profiles')
          .select()
          .eq('id', _userId)
          .maybeSingle(),
      'Could not load your daily targets.',
    );
    if (row == null) return null;

    return NutritionTargets(
      calories: (row['daily_calorie_target'] as num).toInt(),
      protein: (row['protein_target_grams'] as num).toInt(),
      carbs: (row['carb_target_grams'] as num).toInt(),
      fat: (row['fat_target_grams'] as num).toInt(),
    );
  }

  Future<void> saveTargets(NutritionTargets targets) async {
    await _guard(
      () => _client.from('profiles').update({
        'daily_calorie_target': targets.calories,
        'protein_target_grams': targets.protein,
        'carb_target_grams': targets.carbs,
        'fat_target_grams': targets.fat,
      }).eq('id', _userId),
      'Could not save your daily targets.',
    );
  }

  // ---------------------------------------------------------------------

  LoggedFood _loggedFoodFrom(Map<String, dynamic> row) {
    return LoggedFood(
      id: row['id'] as String,
      name: row['name'] as String,
      brandName: row['brand_name'] as String?,
      meal: MealSlot.values.firstWhere(
        (slot) => slot.name == row['meal'],
        orElse: () => MealSlot.snack,
      ),
      servings: _double(row['servings']),
      grams: row['grams'] == null ? null : _double(row['grams']),
      totals: _totalsFrom(row),
      loggedAt: DateTime.parse(row['logged_at'] as String).toLocal(),
    );
  }

  CustomRecipe _recipeFrom(Map<String, dynamic> row) {
    final ingredients =
        (row['recipe_ingredients'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .toList()
          // Postgres does not promise the order of a nested select, so the
          // position column is what actually restores the builder's order.
          ..sort((a, b) => ((a['position'] as num?) ?? 0)
              .compareTo((b['position'] as num?) ?? 0));

    return CustomRecipe(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      yieldServings: (row['yield_servings'] as num).toInt(),
      coverImageUrl: row['cover_image_path'] as String?,
      ingredients: [
        for (final ingredient in ingredients)
          RecipeIngredient(
            id: ingredient['id'] as String,
            name: ingredient['name'] as String,
            grams: _double(ingredient['grams']),
            totals: _totalsFrom(ingredient),
          ),
      ],
    );
  }

  NutritionTotals _totalsFrom(Map<String, dynamic> row) {
    return NutritionTotals(
      calories: _double(row['calories']),
      protein: _double(row['protein_grams']),
      carbs: _double(row['carbs_grams']),
      fat: _double(row['fat_grams']),
      sodium: _double(row['sodium_mg']),
      potassium: _double(row['potassium_mg']),
    );
  }

  /// Postgres `numeric` arrives as a String over PostgREST, not a double —
  /// a plain cast would throw on every nutrient column.
  double _double(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  String _dateOnly(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// Turns Supabase's own exceptions into one type carrying a message fit
  /// to show, so no screen has to know about PostgrestException.
  Future<T> _guard<T>(Future<T> Function() action, String whenFailed) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw NutritionSyncException('$whenFailed ${error.message}');
    } on StorageException catch (error) {
      throw NutritionSyncException('$whenFailed ${error.message}');
    } on AuthException catch (error) {
      throw NutritionSyncException('$whenFailed ${error.message}');
    } on SocketException {
      throw NutritionSyncException('$whenFailed No connection.');
    }
  }
}
