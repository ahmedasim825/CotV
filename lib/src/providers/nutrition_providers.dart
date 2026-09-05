import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/food_models.dart';
import '../services/nutritionix_service.dart';
import 'user_settings_providers.dart';

final nutritionixClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final nutritionixServiceProvider = Provider<NutritionixService>((ref) {
  return NutritionixService(httpClient: ref.watch(nutritionixClientProvider));
});

/// What is currently in the search field, written on every keystroke.
class FoodSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final foodSearchQueryProvider =
    NotifierProvider<FoodSearchQueryNotifier, String>(
  FoodSearchQueryNotifier.new,
);

/// How long the field has to be quiet before a query goes out.
const Duration foodSearchDebounce = Duration(milliseconds: 300);

/// A query shorter than this searches nothing — two letters match most of
/// the database and the result is noise, not a shortlist.
const int foodSearchMinLength = 2;

/// Search results for the current query, debounced.
///
/// The debounce is the provider's rather than the text field's: each
/// keystroke replaces the query, which disposes this future and starts a
/// new one, so only the last keystroke in a burst survives its own delay
/// and reaches the network. A widget-side Timer would have to be
/// cancelled by hand in `dispose`, and would still race the in-flight
/// request it had already started.
final foodSearchProvider =
    FutureProvider.autoDispose<List<FoodSearchHit>>((ref) async {
  final query = ref.watch(foodSearchQueryProvider).trim();
  if (query.length < foodSearchMinLength) return const [];

  var cancelled = false;
  ref.onDispose(() => cancelled = true);

  await Future<void>.delayed(foodSearchDebounce);
  if (cancelled) return const [];

  return ref.watch(nutritionixServiceProvider).searchFoods(query);
});

/// Everything logged today, and what it adds up to.
class DailyNutrition {
  const DailyNutrition({this.entries = const []});

  final List<LoggedFood> entries;

  NutritionTotals get totals => entries.fold(
        NutritionTotals.zero,
        (sum, entry) => sum + entry.totals,
      );

  List<LoggedFood> forMeal(MealSlot meal) =>
      entries.where((entry) => entry.meal == meal).toList();

  NutritionTotals totalsForMeal(MealSlot meal) => forMeal(meal).fold(
        NutritionTotals.zero,
        (sum, entry) => sum + entry.totals,
      );

  bool get isEmpty => entries.isEmpty;
}

/// Today's meal log.
///
/// In memory for this pass, which is why the state is a plain [Notifier]
/// rather than the [StreamNotifier]-over-Hive shape the rest of the app
/// uses: the log is rebuilt from the backend once there is one to sync
/// with, and adding a Hive box now would only have to be migrated then.
class DailyNutritionNotifier extends Notifier<DailyNutrition> {
  @override
  DailyNutrition build() => const DailyNutrition();

  void log(LoggedFood food) {
    state = DailyNutrition(entries: [...state.entries, food]);
  }

  void remove(String id) {
    state = DailyNutrition(
      entries: state.entries.where((entry) => entry.id != id).toList(),
    );
  }

  void clearDay() => state = const DailyNutrition();
}

final dailyNutritionProvider =
    NotifierProvider<DailyNutritionNotifier, DailyNutrition>(
  DailyNutritionNotifier.new,
);

/// The goals today's totals are measured against.
///
/// Falls back to [NutritionTargets.defaults] while the settings record is
/// still loading, so the dashboard ring renders against a real number on
/// its first frame instead of flashing an empty card.
final nutritionTargetsProvider = Provider<NutritionTargets>((ref) {
  return ref.watch(userSettingsControllerProvider).maybeWhen(
        data: NutritionTargets.fromSettings,
        orElse: () => NutritionTargets.defaults,
      );
});

/// The user's own recipes. In memory alongside the meal log, and for the
/// same reason.
class CustomRecipeNotifier extends Notifier<List<CustomRecipe>> {
  @override
  List<CustomRecipe> build() => const [];

  /// Inserts a new recipe, or replaces the one with the same id.
  void save(CustomRecipe recipe) {
    final index = state.indexWhere((existing) => existing.id == recipe.id);
    if (index == -1) {
      state = [...state, recipe];
      return;
    }
    final next = [...state];
    next[index] = recipe;
    state = next;
  }

  void delete(String id) {
    state = state.where((recipe) => recipe.id != id).toList();
  }
}

final customRecipeListProvider =
    NotifierProvider<CustomRecipeNotifier, List<CustomRecipe>>(
  CustomRecipeNotifier.new,
);
