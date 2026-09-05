// Tests for the food logger's arithmetic and its food-API mapping.
//
// The scaling and aggregation live in plain value classes, and the
// mapping runs against payloads captured from the live APIs through a
// `MockClient`, so none of this needs Hive, a platform channel or a
// network.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cotv/src/models/food_models.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/services/food_api_service.dart';
import 'package:cotv/src/ui/food/food_detail_screen.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

/// A food with a round serving weight, so a scaled figure is checkable by
/// eye: one 200 g serving is exactly twice the 100 g basis.
const FoodItem _chicken = FoodItem(
  name: 'grilled chicken breast',
  source: FoodDataSource.usda,
  per100g: NutritionTotals(
    calories: 150,
    protein: 28,
    carbs: 0,
    fat: 3.3,
    sodium: 66,
    potassium: 250,
    fiber: 0,
  ),
  servingWeightGrams: 200,
);

void main() {
  group('FoodItem on a 100 g basis', () {
    const chicken = FoodItem(
      name: 'Chicken breast',
      source: FoodDataSource.usda,
      per100g: NutritionTotals(
        calories: 165, protein: 31, carbs: 0, fat: 3.6,
        sodium: 74, potassium: 256, fiber: 0,
      ),
      servingWeightGrams: 284,
    );

    const broccoli = FoodItem(
      name: 'Broccoli, raw',
      source: FoodDataSource.usda,
      per100g: NutritionTotals(
        calories: 31, protein: 2.57, carbs: 6.27, fat: 0.34,
        sodium: 36, potassium: 303, fiber: 2.4,
      ),
    );

    test('scales by weight straight off the 100 g basis', () {
      expect(chicken.totalsForGrams(200).calories, closeTo(330, 0.001));
      expect(chicken.totalsForGrams(50).protein, closeTo(15.5, 0.001));
    });

    test('one serving is the declared serving weight', () {
      expect(chicken.servingGrams, 284);
      expect(chicken.totalsForServings(1).calories, closeTo(468.6, 0.001));
      expect(chicken.gramsForServings(2), 568);
    });

    test('a food with no declared serving falls back to 100 g', () {
      // USDA Foundation and SR Legacy foods carry servingSize: null, so
      // 100 g is the only basis there is - and it is the one the numbers
      // are quoted on, which makes it the honest default.
      expect(broccoli.hasDeclaredServing, isFalse);
      expect(broccoli.servingGrams, 100);
      expect(broccoli.totalsForServings(1).calories, closeTo(31, 0.001));
      expect(broccoli.basisLabel, 'Per 100 g');
    });

    test('servings and grams invert each other', () {
      expect(chicken.servingsForGrams(568), closeTo(2, 0.001));
      expect(chicken.servingsForGrams(chicken.gramsForServings(1.5)),
          closeTo(1.5, 0.001));
    });

    test('every food can be weighed, so the gram field is never dead', () {
      // The old model returned null grams for a food with no serving
      // weight, which disabled the field. Nothing does that now.
      expect(broccoli.gramsForServings(1), 100);
    });

    test('a declared serving is labelled with its weight', () {
      expect(chicken.basisLabel, '1 serving · 284 g');
    });
  });

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
      final scaled = _chicken.per100g.scaled(1.5);

      expect(scaled.calories, 225);
      expect(scaled.protein, 42);
      expect(scaled.fat, closeTo(4.95, 0.001));
      expect(scaled.sodium, 99);
      expect(scaled.potassium, 375);
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
      final perServing = _chicken.per100g.dividedBy(0);

      expect(perServing.calories, 0);
      expect(perServing.protein, 0);
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


  group('FoodApiService - Open Food Facts', () {
    FoodApiService service(MockClientHandler handler) =>
        FoodApiService(httpClient: MockClient(handler));

    test('identifies the app and a contact, as OFF asks', () async {
      // OFF has no key to authenticate with - this header is the only
      // thing distinguishing the app from anonymous traffic it throttles.
      late http.Request sent;
      final api = service((request) async {
        sent = request;
        return http.Response(jsonEncode(_offNutella), 200);
      });

      await api.getFoodByBarcode('3017620422003');

      expect(sent.headers['User-Agent'], contains('CotVApp'));
      expect(sent.headers['User-Agent'], contains('Contact:'));
      expect(sent.url.toString(),
          'https://world.openfoodfacts.org/api/v2/product/3017620422003.json');
    });

    test('converts sodium and potassium from grams to milligrams', () async {
      // OFF reports both in grams (sodium_unit: "g"). Read as mg,
      // Nutella's 0.0428 would show as 0 mg instead of 43 mg.
      final api =
          service((_) async => http.Response(jsonEncode(_offNutella), 200));

      final food = await api.getFoodByBarcode('3017620422003');

      expect(food.per100g.sodium, closeTo(42.8, 0.01));
      expect(food.per100g.potassium, closeTo(0, 0.01));
      expect(food.per100g.calories, 539);
      expect(food.per100g.protein, closeTo(6.3, 0.001));
      expect(food.source, FoodDataSource.openFoodFacts);
    });

    test('a product with potassium converts that too', () async {
      final api =
          service((_) async => http.Response(jsonEncode(_offChips), 200));

      final food = await api.getFoodByBarcode('028400090858');

      expect(food.per100g.potassium, closeTo(1236.75, 0.01));
      expect(food.servingWeightGrams, 28.3);
    });

    test('reads fiber, which the macro grid now shows', () async {
      final api =
          service((_) async => http.Response(jsonEncode(_offChips), 200));

      expect((await api.getFoodByBarcode('1')).per100g.fiber,
          closeTo(4.4, 0.001));
    });

    test('an unknown barcode is a clear miss, not a crash', () async {
      // OFF answers 200 with status 0 for a code it does not know. A
      // status-code-only check would sail past this and then throw on the
      // missing product key.
      final api = service((_) async => http.Response(
          jsonEncode(
              {'status': 0, 'status_verbose': 'no code or invalid code'}),
          200));

      await expectLater(
        api.getFoodByBarcode('0000000000000'),
        throwsA(isA<FoodApiException>().having(
            (e) => e.message, 'message', contains('0000000000000'))),
      );
    });

    test('falls back to product_name_en when product_name is missing',
        () async {
      final api = service((_) async => http.Response(
          jsonEncode({
            'status': 1,
            'product': {
              'product_name_en': 'Sparkling Water',
              'nutriments': {'energy-kcal_100g': 0},
            },
          }),
          200));

      expect((await api.getFoodByBarcode('1')).name, 'Sparkling Water');
    });

    test('a product with no nutriments reads as zeros, not an exception',
        () async {
      final api = service((_) async => http.Response(
          jsonEncode({
            'status': 1,
            'product': {'product_name': 'Mystery'},
          }),
          200));

      final food = await api.getFoodByBarcode('1');

      expect(food.name, 'Mystery');
      expect(food.per100g.calories, 0);
    });

    test('a serving_quantity string still parses', () async {
      // OFF returns this as an int, a double or a string depending on the
      // product.
      final api = service((_) async => http.Response(
          jsonEncode({
            'status': 1,
            'product': {
              'product_name': 'Yoghurt',
              'serving_quantity': '125',
              'nutriments': {'energy-kcal_100g': 60},
            },
          }),
          200));

      expect((await api.getFoodByBarcode('1')).servingWeightGrams, 125);
    });
  });

  group('FoodApiService - USDA search', () {
    FoodApiService service(MockClientHandler handler,
            {String key = 'test-key'}) =>
        FoodApiService(httpClient: MockClient(handler), usdaApiKey: key);

    test('a blank query short-circuits before any request', () async {
      final api = service((_) async => throw StateError('no request'));
      expect(await api.searchFoods('   '), isEmpty);
    });

    test('reads calories from kcal, never the kJ row', () async {
      // USDA returns Energy twice: id 1062 in kJ and id 1008 in kcal.
      // Matching the name "Energy" picks whichever came first and reports
      // broccoli at 132 kcal instead of 31.
      final api =
          service((_) async => http.Response(jsonEncode(_usdaBroccoli), 200));

      final hits = await api.searchFoods('broccoli');

      expect(hits.single.item.per100g.calories, 31);
      expect(hits.single.item.per100g.potassium, 303);
      expect(hits.single.item.per100g.sodium, 36);
      expect(hits.single.item.per100g.protein, closeTo(2.57, 0.001));
      expect(hits.single.item.source, FoodDataSource.usda);
    });

    test('reads fiber by nutrient id 1079', () async {
      final api =
          service((_) async => http.Response(jsonEncode(_usdaBroccoli), 200));

      expect((await api.searchFoods('broccoli')).single.item.per100g.fiber,
          closeTo(2.4, 0.001));
    });

    test('falls back to the legacy 208 nutrient number when 1008 is absent',
        () async {
      // "208" arrives in nutrientNumber, not nutrientId - matching it
      // against nutrientId would never hit.
      final api = service((_) async => http.Response(
          jsonEncode({
            'totalHits': 1,
            'foods': [
              {
                'description': 'Old Record',
                'dataType': 'SR Legacy',
                'foodNutrients': [
                  {
                    'nutrientNumber': '208',
                    'nutrientName': 'Energy',
                    'value': 88,
                    'unitName': 'KCAL',
                  },
                ],
              },
            ],
          }),
          200));

      expect((await api.searchFoods('x')).single.item.per100g.calories, 88);
    });

    test('converts a kilojoule-only record to kcal', () async {
      // 132 kJ / 4.184 = 31.5 kcal. Reporting 0 for a real food would be
      // worse than converting.
      final api = service((_) async => http.Response(
          jsonEncode({
            'totalHits': 1,
            'foods': [
              {
                'description': 'Kilojoule Only',
                'dataType': 'Foundation',
                'foodNutrients': [
                  {
                    'nutrientId': 1062,
                    'nutrientName': 'Energy',
                    'value': 132,
                    'unitName': 'kJ',
                  },
                ],
              },
            ],
          }),
          200));

      expect((await api.searchFoods('x')).single.item.per100g.calories,
          closeTo(31.55, 0.01));
    });

    test('a genuinely zero-calorie food stays zero, not converted', () async {
      // Water carries 1008 = 0. The fallback chain must not mistake that
      // for "missing" and go hunting for a kJ row to inflate it with.
      final api = service((_) async => http.Response(
          jsonEncode({
            'totalHits': 1,
            'foods': [
              {
                'description': 'Water, bottled',
                'dataType': 'Foundation',
                'foodNutrients': [
                  {'nutrientId': 1008, 'value': 0, 'unitName': 'KCAL'},
                  {'nutrientId': 1062, 'value': 0, 'unitName': 'kJ'},
                ],
              },
            ],
          }),
          200));

      expect(
          (await api.searchFoods('water')).single.item.per100g.calories, 0);
    });

    test('a generic food has no declared serving and reads per 100 g',
        () async {
      final api =
          service((_) async => http.Response(jsonEncode(_usdaBroccoli), 200));

      final food = (await api.searchFoods('broccoli')).single.item;

      expect(food.hasDeclaredServing, isFalse);
      expect(food.basisLabel, 'Per 100 g');
    });

    test('a branded food keeps its gram serving size', () async {
      final api =
          service((_) async => http.Response(jsonEncode(_usdaBranded), 200));

      final food = (await api.searchFoods('chicken breast')).single.item;

      expect(food.servingWeightGrams, 284);
      expect(food.brandName, 'GIANT EAGLE');
    });

    test('ranks whole foods first, then survey, then branded', () async {
      // USDA's own ordering buries the raw cut under supermarket packages.
      final api =
          service((_) async => http.Response(jsonEncode(_usdaMixed), 200));

      final hits = await api.searchFoods('chicken breast');

      expect(hits.map((h) => h.item.name).toList(), [
        'Chicken, broilers, breast, raw',
        'Chicken, breast, roasted',
        'Chicken breast, rotisserie',
        'CHICKEN BREAST',
      ]);
      expect(hits.first.isBranded, isFalse);
    });

    test('holds USDA relevance order within one data type', () async {
      // The sort must not shuffle equals: USDA already ranked these two
      // against each other and knows the query better than a tie-break.
      final api = service(
          (_) async => http.Response(jsonEncode(_usdaTwoBranded), 200));

      final hits = await api.searchFoods('cola');

      expect(hits.map((h) => h.item.name).toList(), ['COLA A', 'COLA B']);
    });

    test('an unfamiliar data type sorts last, not first', () async {
      final api = service((_) async => http.Response(
          jsonEncode({
            'totalHits': 2,
            'foods': [
              {
                'description': 'Something New',
                'dataType': 'Experimental',
                'foodNutrients': <Object>[],
              },
              {
                'description': 'Broccoli, raw',
                'dataType': 'Foundation',
                'foodNutrients': <Object>[],
              },
            ],
          }),
          200));

      expect((await api.searchFoods('x')).first.item.name, 'Broccoli, raw');
    });

    test('sends the query and the key, and asks for every data group',
        () async {
      late http.Request sent;
      final api = service((request) async {
        sent = request;
        return http.Response(jsonEncode(_usdaBroccoli), 200);
      });

      await api.searchFoods('oats');

      expect(sent.url.queryParameters['query'], 'oats');
      expect(sent.url.queryParameters['api_key'], 'test-key');
      expect(sent.url.queryParameters['dataType'], contains('Foundation'));
      expect(sent.url.queryParameters['dataType'], contains('Branded'));
    });

    test('a rejected key says so', () async {
      final api = service((_) async => http.Response(
          jsonEncode({
            'error': {'code': 'API_KEY_INVALID'},
          }),
          403));

      await expectLater(
        api.searchFoods('oats'),
        throwsA(isA<FoodApiException>()
            .having((e) => e.message, 'message', contains('USDA API key'))),
      );
    });

    test('a rate-limited DEMO_KEY names the cause', () async {
      // DEMO_KEY is ~30 requests an hour per IP; a debounced search field
      // burns that fast, and "429" alone would not explain why.
      final api =
          service((_) async => http.Response('{}', 429), key: 'DEMO_KEY');

      await expectLater(
        api.searchFoods('oats'),
        throwsA(isA<FoodApiException>()
            .having((e) => e.message, 'message', contains('DEMO_KEY'))),
      );
    });
  });

  group('FoodApiService - regional fallback', () {
    test('asks Open Food Facts when USDA finds nothing', () async {
      // USDA has no Pakistani supermarket brands; OFF does. Verified
      // live: "shan masala" is 0 from USDA and 21 from OFF.
      final requested = <String>[];
      final api = FoodApiService(
        httpClient: MockClient((request) async {
          requested.add(request.url.host);
          if (request.url.host.contains('nal.usda.gov')) {
            return http.Response(
                jsonEncode({'totalHits': 0, 'foods': <Object>[]}), 200);
          }
          return http.Response(jsonEncode(_offSearchShan), 200);
        }),
        usdaApiKey: 'test-key',
      );

      final hits = await api.searchFoods('shan masala');

      expect(requested, ['api.nal.usda.gov', 'world.openfoodfacts.org']);
      expect(hits.single.item.name, 'Chana masala mix');
      expect(hits.single.item.source, FoodDataSource.openFoodFacts);
      expect(hits.single.item.per100g.fiber, 10);
    });

    test('does not ask OFF when USDA already answered', () async {
      // The fallback is for empty results, not a second opinion - an
      // extra round trip on every successful search would be pure latency.
      final requested = <String>[];
      final api = FoodApiService(
        httpClient: MockClient((request) async {
          requested.add(request.url.host);
          return http.Response(jsonEncode(_usdaBroccoli), 200);
        }),
        usdaApiKey: 'test-key',
      );

      await api.searchFoods('broccoli');

      expect(requested, ['api.nal.usda.gov']);
    });

    test('a failing fallback returns nothing rather than an error', () async {
      // OFF's legacy CGI search 503s intermittently - observed once
      // during planning, then fine on retry. "USDA found nothing" must
      // not become a red error card because the optional lookup flaked.
      final api = FoodApiService(
        httpClient: MockClient((request) async {
          if (request.url.host.contains('nal.usda.gov')) {
            return http.Response(
                jsonEncode({'totalHits': 0, 'foods': <Object>[]}), 200);
          }
          return http.Response('upstream unavailable', 503);
        }),
        usdaApiKey: 'test-key',
      );

      expect(await api.searchFoods('shan masala'), isEmpty);
    });

    test('a barcode failure still raises, unlike the fallback', () async {
      // Only the fallback swallows failures. A scan the user is waiting
      // on must still say what went wrong.
      final api = FoodApiService(
        httpClient: MockClient((_) async => http.Response('nope', 503)),
      );

      await expectLater(
        api.getFoodByBarcode('3017620422003'),
        throwsA(isA<FoodApiException>()),
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

/// The minimum a food screen needs: a themed [MaterialApp] over a scope.
Widget _harness(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(AppThemeVariant.sanctuary),
        home: Scaffold(body: child),
      ),
    );

/// Trimmed from the live OFF response for Nutella (3017620422003).
const Map<String, dynamic> _offNutella = {
  'status': 1,
  'product': {
    'product_name': 'Nutella',
    'brands': 'Nutella, Ferrero',
    'image_front_url': 'https://images.openfoodfacts.test/nutella-front.jpg',
    'image_small_url': 'https://images.openfoodfacts.test/nutella-small.jpg',
    'serving_quantity': null,
    'nutriments': {
      'energy-kcal_100g': 539,
      'proteins_100g': 6.3,
      'carbohydrates_100g': 57.5,
      'fat_100g': 30.9,
      'sodium_100g': 0.0428,
      'sodium_unit': 'g',
      'potassium_100g': null,
    },
  },
};

/// Trimmed from the live OFF response for Lays (028400090858).
const Map<String, dynamic> _offChips = {
  'status': 1,
  'product': {
    'product_name': 'Lays Classic',
    'serving_quantity': 28.3,
    'serving_size': '1 portion (28.3 g)',
    'nutriments': {
      'energy-kcal_100g': 565.371024734982,
      'proteins_100g': 6.6,
      'carbohydrates_100g': 53,
      'fat_100g': 35.3,
      'fiber_100g': 4.4,
      'sodium_100g': 0.49469964664311,
      'sodium_unit': 'g',
      'potassium_100g': 1.23674911660777,
      'potassium_unit': 'g',
    },
  },
};

/// Trimmed from the live OFF text search for "shan masala".
const Map<String, dynamic> _offSearchShan = {
  'count': 21,
  'products': [
    {
      'product_name': 'Chana masala mix',
      'brands': 'Shan',
      'nutriments': {
        'energy-kcal_100g': 250,
        'proteins_100g': 9,
        'carbohydrates_100g': 40,
        'fat_100g': 5,
        'fiber_100g': 10,
        'sodium_100g': 4.2,
        'sodium_unit': 'g',
      },
    },
  ],
};

/// Trimmed from the live USDA search for "raw broccoli". Note Energy
/// appearing twice, kJ first - the ordering that breaks a name match.
const Map<String, dynamic> _usdaBroccoli = {
  'totalHits': 1,
  'foods': [
    {
      'description': 'Broccoli, raw',
      'dataType': 'Foundation',
      'servingSize': null,
      'servingSizeUnit': null,
      'foodNutrients': [
        {
          'nutrientId': 1062,
          'nutrientName': 'Energy',
          'value': 132,
          'unitName': 'kJ',
        },
        {
          'nutrientId': 1008,
          'nutrientName': 'Energy',
          'value': 31.0,
          'unitName': 'KCAL',
        },
        {
          'nutrientId': 1003,
          'nutrientName': 'Protein',
          'value': 2.57,
          'unitName': 'G',
        },
        {
          'nutrientId': 1005,
          'nutrientName': 'Carbohydrate, by difference',
          'value': 6.27,
          'unitName': 'G',
        },
        {
          'nutrientId': 1004,
          'nutrientName': 'Total lipid (fat)',
          'value': 0.34,
          'unitName': 'G',
        },
        {
          'nutrientId': 1079,
          'nutrientName': 'Fiber, total dietary',
          'value': 2.4,
          'unitName': 'G',
        },
        {
          'nutrientId': 1093,
          'nutrientName': 'Sodium, Na',
          'value': 36.0,
          'unitName': 'MG',
        },
        {
          'nutrientId': 1092,
          'nutrientName': 'Potassium, K',
          'value': 303,
          'unitName': 'MG',
        },
      ],
    },
  ],
};

/// Trimmed from the live USDA search for "chicken breast".
const Map<String, dynamic> _usdaBranded = {
  'totalHits': 1,
  'foods': [
    {
      'description': 'CHICKEN BREAST',
      'dataType': 'Branded',
      'brandName': 'GIANT EAGLE',
      'brandOwner': 'Giant Eagle, Inc.',
      'servingSize': 284.0,
      'servingSizeUnit': 'g',
      'foodNutrients': [
        {'nutrientId': 1008, 'value': 165, 'unitName': 'KCAL'},
        {'nutrientId': 1003, 'value': 20.4, 'unitName': 'G'},
        {'nutrientId': 1005, 'value': 1.06, 'unitName': 'G'},
        {'nutrientId': 1004, 'value': 8.1, 'unitName': 'G'},
        {'nutrientId': 1093, 'value': 433, 'unitName': 'MG'},
      ],
    },
  ],
};

/// All four data types, branded first - the order USDA actually returns
/// them in. Verified live: a real 25-item page for "chicken breast" comes
/// back 10 Branded, 8 Survey, 4 SR Legacy, 3 Foundation.
const Map<String, dynamic> _usdaMixed = {
  'totalHits': 4,
  'foods': [
    {
      'description': 'CHICKEN BREAST',
      'dataType': 'Branded',
      'brandName': 'GIANT EAGLE',
      'servingSize': 284.0,
      'servingSizeUnit': 'g',
      'foodNutrients': [
        {'nutrientId': 1008, 'value': 165, 'unitName': 'KCAL'},
      ],
    },
    {
      'description': 'Chicken breast, rotisserie',
      'dataType': 'Survey (FNDDS)',
      'foodNutrients': [
        {'nutrientId': 1008, 'value': 148, 'unitName': 'KCAL'},
      ],
    },
    {
      'description': 'Chicken, breast, roasted',
      'dataType': 'SR Legacy',
      'foodNutrients': [
        {'nutrientId': 1008, 'value': 165, 'unitName': 'KCAL'},
      ],
    },
    {
      'description': 'Chicken, broilers, breast, raw',
      'dataType': 'Foundation',
      'foodNutrients': [
        {'nutrientId': 1008, 'value': 114, 'unitName': 'KCAL'},
      ],
    },
  ],
};

/// Two entries of the same data type, to pin the tie-break.
const Map<String, dynamic> _usdaTwoBranded = {
  'totalHits': 2,
  'foods': [
    {
      'description': 'COLA A',
      'dataType': 'Branded',
      'foodNutrients': <Object>[],
    },
    {
      'description': 'COLA B',
      'dataType': 'Branded',
      'foodNutrients': <Object>[],
    },
  ],
};
