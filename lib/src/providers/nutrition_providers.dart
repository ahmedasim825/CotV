import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/food_models.dart';
import '../services/nutrition_sync_service.dart';
import '../services/food_api_service.dart';
import 'auth_providers.dart';
import 'user_settings_providers.dart';

final foodApiClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final foodApiServiceProvider = Provider<FoodApiService>((ref) {
  return FoodApiService(httpClient: ref.watch(foodApiClientProvider));
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
///
/// A keystroke can cost two round trips now: USDA, then Open Food Facts
/// when USDA has nothing. 450 ms is long enough that typing a word is one
/// search rather than six, and short enough not to feel laggy.
const Duration foodSearchDebounce = Duration(milliseconds: 450);

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

  return ref.watch(foodApiServiceProvider).searchFoods(query);
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
/// Local first, synced when there is an account behind it. Writes land in
/// [state] immediately and go to Supabase afterwards, so logging a food is
/// never blocked on the network — the ring moves as soon as the button is
/// pressed. A failed write surfaces in [syncError] and leaves the local
/// entry alone rather than yanking a row back out from under the user.
///
/// Signing in reloads the day from the server, which is also what makes a
/// second device show what the first one logged.
class DailyNutritionNotifier extends Notifier<DailyNutrition> {
  NutritionSyncService? get _sync => ref.read(nutritionSyncServiceProvider);

  @override
  DailyNutrition build() {
    // Re-runs on sign-in and sign-out. Signing out drops back to an empty
    // local log rather than leaving the previous account's food on screen.
    final signedIn = ref.watch(isSignedInProvider);
    if (signedIn) Future.microtask(refresh);
    return const DailyNutrition();
  }

  /// Replaces the local log with today's rows from the server.
  Future<void> refresh() async {
    final sync = _sync;
    if (sync == null) return;
    try {
      final entries = await sync.fetchLog(DateTime.now());
      state = DailyNutrition(entries: entries);
      ref.read(syncErrorProvider.notifier).clear();
    } on NutritionSyncException catch (error) {
      ref.read(syncErrorProvider.notifier).set(error.message);
    }
  }

  Future<void> log(LoggedFood food) async {
    state = DailyNutrition(entries: [...state.entries, food]);
    await _push(() => _sync?.insertLoggedFood(food, DateTime.now()));
  }

  Future<void> remove(String id) async {
    state = DailyNutrition(
      entries: state.entries.where((entry) => entry.id != id).toList(),
    );
    await _push(() => _sync?.deleteLoggedFood(id));
  }

  void clearDay() => state = const DailyNutrition();

  Future<void> _push(Future<void>? Function() write) async {
    try {
      await write();
      ref.read(syncErrorProvider.notifier).clear();
    } on NutritionSyncException catch (error) {
      ref.read(syncErrorProvider.notifier).set(error.message);
    }
  }
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

/// The user's own recipes. Local first and synced, like the meal log.
class CustomRecipeNotifier extends Notifier<List<CustomRecipe>> {
  NutritionSyncService? get _sync => ref.read(nutritionSyncServiceProvider);

  @override
  List<CustomRecipe> build() {
    final signedIn = ref.watch(isSignedInProvider);
    if (signedIn) Future.microtask(refresh);
    return const [];
  }

  Future<void> refresh() async {
    final sync = _sync;
    if (sync == null) return;
    try {
      state = await sync.fetchRecipes();
      ref.read(syncErrorProvider.notifier).clear();
    } on NutritionSyncException catch (error) {
      ref.read(syncErrorProvider.notifier).set(error.message);
    }
  }

  /// Inserts a new recipe, or replaces the one with the same id.
  Future<void> save(CustomRecipe recipe) async {
    final index = state.indexWhere((existing) => existing.id == recipe.id);
    if (index == -1) {
      state = [...state, recipe];
    } else {
      final next = [...state];
      next[index] = recipe;
      state = next;
    }
    await _push(() => _sync?.saveRecipe(recipe));
  }

  Future<void> delete(String id) async {
    state = state.where((recipe) => recipe.id != id).toList();
    await _push(() => _sync?.deleteRecipe(id));
  }

  Future<void> _push(Future<void>? Function() write) async {
    try {
      await write();
      ref.read(syncErrorProvider.notifier).clear();
    } on NutritionSyncException catch (error) {
      ref.read(syncErrorProvider.notifier).set(error.message);
    }
  }
}

final customRecipeListProvider =
    NotifierProvider<CustomRecipeNotifier, List<CustomRecipe>>(
  CustomRecipeNotifier.new,
);

/// The last sync failure, or null when the last write went through.
///
/// One shared slot rather than an error field on each notifier: the user
/// cares that syncing is broken, not which of two writes noticed first.
class SyncErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String message) => state = message;

  void clear() {
    if (state != null) state = null;
  }
}

final syncErrorProvider =
    NotifierProvider<SyncErrorNotifier, String?>(SyncErrorNotifier.new);

/// A cover reference resolved to something an Image widget can load.
///
/// Two different kinds of value reach [CustomRecipe.coverImageUrl]: a URL
/// the user typed into the builder, and an object path in the private
/// `recipe-covers` bucket that an upload produced. Only the second needs
/// signing, and a signed URL expires — which is why this resolves at
/// render time instead of being stored alongside the recipe.
///
/// Returns null rather than throwing when there is no session to sign
/// with, so the tile falls back to its plate glyph.
final recipeCoverUrlProvider =
    FutureProvider.autoDispose.family<String?, String?>((ref, reference) async {
  if (reference == null || reference.isEmpty) return null;
  if (reference.startsWith('http')) return reference;

  final sync = ref.watch(nutritionSyncServiceProvider);
  if (sync == null) return null;

  try {
    return await sync.signedCoverUrl(reference);
  } on NutritionSyncException {
    return null;
  }
});
