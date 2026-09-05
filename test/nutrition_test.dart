// Tests for the food logger's arithmetic and its Nutritionix mapping.
//
// The scaling and aggregation live in plain value classes, and the mapping
// runs against captured payloads through a `MockClient`, so none of this
// needs Hive, a platform channel or a network.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cotv/src/models/food_models.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/services/nutritionix_service.dart';
import 'package:cotv/src/ui/food/food_detail_screen.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

/// A food with a round serving weight, so a scaled figure is checkable by
/// eye: 100 g is exactly half a serving.
const FoodItem _chicken = FoodItem(
  name: 'grilled chicken breast',
  perServing: NutritionTotals(
    calories: 300,
    protein: 56,
    carbs: 0,
    fat: 6.6,
    sodium: 132,
    potassium: 500,
  ),
  servingQty: 1,
  servingUnit: 'breast',
  servingWeightGrams: 200,
);

void main() {
  group('NutritionTotals', () {
    test('carries fiber through scaling, addition and division', () {
      const meal = NutritionTotals(
        calories: 200, protein: 10, carbs: 30, fat: 5,
        sodium: 100, potassium: 250, fiber: 4,
      );

      expect(meal.scaled(2.5).fiber, closeTo(10, 0.001));
      expect((meal + meal).fiber, closeTo(8, 0.001));
      expect(meal.dividedBy(4).fiber, closeTo(1, 0.001));
      expect(NutritionTotals.zero.fiber, 0);
    });

    test('fiber defaults to zero so existing call sites still compile', () {
      // Every database the app talks to omits fiber for some foods, and
      // the sync layer wrote six columns before this change. A required
      // seventh parameter would break both.
      const noFiber = NutritionTotals(
        calories: 100, protein: 1, carbs: 2, fat: 3, sodium: 4, potassium: 5,
      );
      expect(noFiber.fiber, 0);
    });

    test('scales every nutrient by the same factor', () {
      final scaled = _chicken.perServing.scaled(1.5);

      expect(scaled.calories, 450);
      expect(scaled.protein, 84);
      expect(scaled.fat, closeTo(9.9, 0.001));
      expect(scaled.sodium, 198);
      expect(scaled.potassium, 750);
    });

    test('adds nutrient by nutrient', () {
      const a = NutritionTotals(
        calories: 100,
        protein: 10,
        carbs: 5,
        fat: 2,
        sodium: 50,
        potassium: 80,
      );
      const b = NutritionTotals(
        calories: 40,
        protein: 1,
        carbs: 9,
        fat: 3,
        sodium: 10,
        potassium: 20,
      );

      final sum = a + b;

      expect(sum.calories, 140);
      expect(sum.protein, 11);
      expect(sum.carbs, 14);
      expect(sum.fat, 5);
      expect(sum.sodium, 60);
      expect(sum.potassium, 100);
    });

    test('dividing by a yield of zero returns zero, not infinity', () {
      final perServing = _chicken.perServing.dividedBy(0);

      expect(perServing.calories, 0);
      expect(perServing.protein, 0);
    });
  });

  group('FoodItem', () {
    test("servings and grams agree at the food's own serving weight", () {
      final byServing = _chicken.totalsForServings(1.5);
      final byWeight = _chicken.totalsForGrams(300);

      expect(byWeight.calories, byServing.calories);
      expect(byWeight.protein, byServing.protein);
      expect(byWeight.potassium, byServing.potassium);
    });

    test('converts between servings and grams in both directions', () {
      expect(_chicken.servingsForGrams(100), 0.5);
      expect(_chicken.gramsForServings(2.5), 500);
    });

    test('a food with no serving weight cannot be logged by weight', () {
      const soup = FoodItem(
        name: 'soup',
        perServing: NutritionTotals(
          calories: 120,
          protein: 4,
          carbs: 18,
          fat: 3,
          sodium: 890,
          potassium: 300,
        ),
      );

      expect(soup.canWeigh, isFalse);
      expect(soup.gramsForServings(2), isNull);
      // Falls back to one serving rather than producing a NaN.
      expect(soup.totalsForGrams(250).calories, 120);
    });
  });

  group('CustomRecipe', () {
    const recipe = CustomRecipe(
      id: 'r1',
      title: 'Chicken and rice',
      yieldServings: 4,
      ingredients: [
        RecipeIngredient(
          id: 'i1',
          name: 'chicken breast',
          grams: 600,
          totals: NutritionTotals(
            calories: 900,
            protein: 168,
            carbs: 0,
            fat: 19.8,
            sodium: 396,
            potassium: 1500,
          ),
        ),
        RecipeIngredient(
          id: 'i2',
          name: 'white rice',
          grams: 400,
          totals: NutritionTotals(
            calories: 520,
            protein: 10,
            carbs: 112,
            fat: 1.2,
            sodium: 4,
            potassium: 140,
          ),
        ),
      ],
    );

    test('totals are the sum of the ingredients', () {
      expect(recipe.total.calories, 1420);
      expect(recipe.total.protein, 178);
      expect(recipe.total.carbs, 112);
      expect(recipe.totalGrams, 1000);
    });

    test('per serving is the total over the yield', () {
      expect(recipe.perServing.calories, 355);
      expect(recipe.perServing.protein, 44.5);
      expect(recipe.perServing.carbs, 28);
      expect(recipe.perServing.potassium, 410);
    });
  });

  group('NutritionTargets', () {
    test('an unconfigured record gets every default', () {
      final targets = NutritionTargets.fromSettings(UserSettings());

      expect(targets.calories, 2000);
      expect(targets.protein, 150);
      expect(targets.carbs, 220);
      expect(targets.fat, 70);
    });

    test('falls back per field, not all-or-nothing', () {
      final targets = NutritionTargets.fromSettings(
        UserSettings(dailyCalorieTarget: 2600),
      );

      expect(targets.calories, 2600);
      // The three the user never set keep their defaults.
      expect(targets.protein, 150);
      expect(targets.carbs, 220);
      expect(targets.fat, 70);
    });

    test('a stored zero falls back, since every target is a divisor', () {
      final targets = NutritionTargets.fromSettings(
        UserSettings(dailyCalorieTarget: 0),
      );

      expect(targets.calories, 2000);
    });
  });

  group('NutritionixService', () {
    test('refuses to call anything while the keys are placeholders', () async {
      final service = NutritionixService(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(service.isConfigured, isFalse);
      await expectLater(
        service.searchFoods('chicken'),
        throwsA(
          isA<NutritionixException>().having(
            (error) => error.message,
            'message',
            contains('keys are not set'),
          ),
        ),
      );
    });

    test('a blank query short-circuits before any request', () async {
      final service = _service((_) async => throw StateError('no request'));

      expect(await service.searchFoods('   '), isEmpty);
    });

    test('sends the credentials as headers, never in the URL', () async {
      late http.Request sent;
      final service = _service((request) async {
        sent = request;
        return http.Response(
          jsonEncode({'common': <Object>[], 'branded': <Object>[]}),
          200,
        );
      });

      await service.searchFoods('chicken');

      expect(sent.headers['x-app-id'], 'test-id');
      expect(sent.headers['x-app-key'], 'test-key');
      expect(sent.headers['x-remote-user-id'], '0');
      expect(sent.url.queryParameters['query'], 'chicken');
      expect(sent.url.toString(), isNot(contains('test-key')));
    });

    test('merges common and branded hits, common first', () async {
      final service = _service(
        (_) async => http.Response(jsonEncode(_instantBody), 200),
      );

      final hits = await service.searchFoods('cola');

      expect(hits, hasLength(2));
      expect(hits.first.name, 'cola');
      expect(hits.first.isBranded, isFalse);
      // A common hit carries a serving but no calories.
      expect(hits.first.servingPreview, '1 fl oz');
      expect(hits.first.caloriesPreview, isNull);

      expect(hits.last.name, 'Coca-Cola Classic');
      expect(hits.last.isBranded, isTrue);
      expect(hits.last.brandName, 'Coca-Cola');
      expect(hits.last.caloriesPreview, 140);
    });

    test('reads every nutrient the logger shows', () async {
      final service = _service(
        (_) async => http.Response(jsonEncode(_naturalNutrientsBody), 200),
      );

      final food = await service.getFoodDetails('grilled chicken breast');

      expect(food.name, 'grilled chicken breast');
      expect(food.brandName, isNull);
      expect(food.perServing.calories, 284.31);
      expect(food.perServing.protein, 53.4);
      expect(food.perServing.carbs, 0);
      expect(food.perServing.fat, 6.18);
      expect(food.servingWeightGrams, 174);
      expect(food.servingUnit, 'breast');
      expect(food.thumbUrl, contains('thumb'));
      expect(food.highresUrl, contains('highres'));
    });

    test('falls back to full_nutrients when nf_potassium is null', () async {
      final service = _service(
        (_) async => http.Response(jsonEncode(_naturalNutrientsBody), 200),
      );

      final food = await service.getFoodDetails('grilled chicken breast');

      // The payload carries `nf_potassium: null` with the real value under
      // attr_id 306, which is the common shape from /natural/nutrients.
      expect(food.perServing.potassium, 440.22);
      expect(food.perServing.sodium, 127.02);
    });

    test('a barcode lookup keeps the brand and the UPC', () async {
      late Uri requested;
      final service = _service((request) async {
        requested = request.url;
        return http.Response(jsonEncode(_barcodeBody), 200);
      });

      final food = await service.getFoodByBarcode('049000006346');

      expect(requested.path, endsWith('/search/item'));
      expect(requested.queryParameters['upc'], '049000006346');
      expect(food.name, 'Coca-Cola Classic');
      expect(food.brandName, 'Coca-Cola');
      expect(food.upc, '049000006346');
      expect(food.perServing.calories, 140);
      expect(food.perServing.sodium, 45);
    });

    test('a missing nutrient reads as zero rather than throwing', () async {
      final service = _service(
        (_) async => http.Response(
          jsonEncode({
            'foods': [
              {'food_name': 'plain water', 'nf_calories': 0},
            ],
          }),
          200,
        ),
      );

      final food = await service.getFoodByBarcode('1');

      expect(food.perServing.protein, 0);
      expect(food.perServing.potassium, 0);
      expect(food.servingWeightGrams, isNull);
      expect(food.canWeigh, isFalse);
    });

    test('a 401 names the credentials', () async {
      final service = _service((_) async => http.Response('{}', 401));

      await expectLater(
        service.getFoodDetails('chicken'),
        throwsA(
          isA<NutritionixException>().having(
            (error) => error.message,
            'message',
            contains('app id and key'),
          ),
        ),
      );
    });

    test('an unknown barcode reports the barcode, not a status code', () async {
      final service = _service((_) async => http.Response('{}', 404));

      await expectLater(
        service.getFoodByBarcode('000000000000'),
        throwsA(
          isA<NutritionixException>().having(
            (error) => error.message,
            'message',
            contains('000000000000'),
          ),
        ),
      );
    });

    test('an empty foods array is a not-found, not a crash', () async {
      final service = _service(
        (_) async => http.Response(jsonEncode({'foods': <Object>[]}), 200),
      );

      await expectLater(
        service.getFoodDetails('unicorn steak'),
        throwsA(isA<NutritionixException>()),
      );
    });
  });

  group('FoodDetailScreen', () {
    testWidgets('scales the readout as the serving count changes',
        (tester) async {
      _openViewport(tester);
      await tester.pumpWidget(_harness(const FoodDetailScreen(food: _chicken)));

      // One serving, as opened.
      expect(find.text('300'), findsOneWidget);
      expect(find.text('56.0g'), findsOneWidget);

      // Pumped between taps: the stepper's callback closes over the
      // serving count from the last build, so two taps on one frame would
      // both compute the same 1.5.
      await tester.tap(find.bySemanticsLabel('More servings'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('More servings'));
      await tester.pumpAndSettle();

      expect(find.text('600'), findsOneWidget);
      expect(find.text('112.0g'), findsOneWidget);
      // The gram field tracks the stepper.
      expect(find.text('400'), findsOneWidget);
    });

    testWidgets('typing grams drives the serving count', (tester) async {
      _openViewport(tester);
      await tester.pumpWidget(_harness(const FoodDetailScreen(food: _chicken)));

      await tester.enterText(find.byType(TextField).first, '100');
      await tester.pumpAndSettle();

      // 100 g of a 200 g serving is half of it.
      expect(find.text('0.5'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
    });
  });
}

/// Gives the test a surface tall enough to hold the whole configurator.
///
/// The screen is a lazily-built [ListView], so on the default 800x600 test
/// window the portion controls and the macro readout are never constructed
/// and nothing below the hero image can be found or tapped.
void _openViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A service with credentials, so the endpoints can be exercised without
/// the build carrying real keys.
NutritionixService _service(MockClientHandler handler) => NutritionixService(
      httpClient: MockClient(handler),
      appId: 'test-id',
      appKey: 'test-key',
    );

/// The minimum a food screen needs: a themed [MaterialApp] over a scope.
Widget _harness(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(AppThemeVariant.sanctuary),
        home: Scaffold(body: child),
      ),
    );

/// A captured `/search/instant` response, trimmed to the fields the result
/// list reads.
const Map<String, dynamic> _instantBody = {
  'common': [
    {
      'food_name': 'cola',
      'serving_qty': 1,
      'serving_unit': 'fl oz',
      'photo': {'thumb': 'https://nix-tag-images.test/thumb/cola.jpg'},
    },
  ],
  'branded': [
    {
      'food_name': 'Coca-Cola Classic',
      'brand_name': 'Coca-Cola',
      'serving_qty': 12,
      'serving_unit': 'fl oz',
      'nf_calories': 140,
      'photo': {'thumb': 'https://nix-tag-images.test/thumb/coke.jpg'},
    },
  ],
};

/// A captured `/natural/nutrients` response. `nf_potassium` and `nf_sodium`
/// are null while the values sit in `full_nutrients` — the case the
/// fallback exists for.
const Map<String, dynamic> _naturalNutrientsBody = {
  'foods': [
    {
      'food_name': 'grilled chicken breast',
      'brand_name': null,
      'serving_qty': 1,
      'serving_unit': 'breast',
      'serving_weight_grams': 174,
      'nf_calories': 284.31,
      'nf_total_fat': 6.18,
      'nf_total_carbohydrate': 0,
      'nf_protein': 53.4,
      'nf_sodium': null,
      'nf_potassium': null,
      'full_nutrients': [
        {'attr_id': 203, 'value': 53.4},
        {'attr_id': 306, 'value': 440.22},
        {'attr_id': 307, 'value': 127.02},
      ],
      'photo': {
        'thumb': 'https://nix-tag-images.test/thumb/chicken.jpg',
        'highres': 'https://nix-tag-images.test/highres/chicken.jpg',
      },
    },
  ],
};

/// A captured `/search/item` (barcode) response.
const Map<String, dynamic> _barcodeBody = {
  'foods': [
    {
      'food_name': 'Coca-Cola Classic',
      'brand_name': 'Coca-Cola',
      'serving_qty': 1,
      'serving_unit': 'can',
      'serving_weight_grams': 355,
      'nf_calories': 140,
      'nf_total_fat': 0,
      'nf_total_carbohydrate': 39,
      'nf_protein': 0,
      'nf_sodium': 45,
      'nf_potassium': 0,
      'upc': '049000006346',
      'photo': {'thumb': 'https://nix-tag-images.test/thumb/coke.jpg'},
    },
  ],
};
