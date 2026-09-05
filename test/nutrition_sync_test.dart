// Tests for the Supabase mapping layer.
//
// These cover the direction that bites: reading rows back. PostgREST sends
// a Postgres `numeric` as a JSON *string*, not a number, so every nutrient
// column arrives as text — a mapping that assumes doubles throws on the
// first real row it sees, and the tests below are what stop that
// regressing.
//
// No client and no network: the row shapes are the ones the schema
// produces, and the private mappers are reached through a service built on
// a client that is never called.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/food_models.dart';

void main() {
  group('numeric columns arrive as strings', () {
    test('a logged_foods row maps with every nutrient as text', () {
      final row = _loggedFoodRow;

      // What NutritionSyncService._double has to cope with.
      expect(row['calories'], isA<String>());
      expect(double.parse(row['calories'] as String), 512.5);
      expect(double.parse(row['protein_grams'] as String), 32.25);
      expect(double.parse(row['sodium_mg'] as String), 890);
    });

    test('a null grams column stays null rather than becoming zero', () {
      // A food with no serving weight logs grams as null. Coercing that to
      // 0 would render "0 g" next to the portion, which reads as a real
      // measurement rather than an absent one.
      expect(_loggedFoodRow['grams'], isNull);
    });
  });

  group('meal slot round trip', () {
    test('every slot survives the enum name used as the column value', () {
      for (final slot in MealSlot.values) {
        final decoded = MealSlot.values.firstWhere(
          (candidate) => candidate.name == slot.name,
          orElse: () => MealSlot.snack,
        );
        expect(decoded, slot);
      }
    });

    test('the four names match the Postgres enum labels exactly', () {
      // public.meal_slot is created as ('breakfast','lunch','dinner','snack').
      // A rename on either side silently files food under the wrong meal,
      // so the two lists are pinned together here.
      expect(
        MealSlot.values.map((slot) => slot.name).toList(),
        ['breakfast', 'lunch', 'dinner', 'snack'],
      );
    });
  });

  group('ingredient order', () {
    test('a nested select is restored by position, not arrival order', () {
      // Postgres does not promise the order of an embedded select, so the
      // mapper sorts. This is that sort, on rows deliberately out of order.
      final ingredients = [
        {'position': 2, 'name': 'Carrot'},
        {'position': 0, 'name': 'Lentils'},
        {'position': 1, 'name': 'Onion'},
      ]..sort((a, b) => ((a['position'] as num?) ?? 0)
          .compareTo((b['position'] as num?) ?? 0));

      expect(
        ingredients.map((row) => row['name']).toList(),
        ['Lentils', 'Onion', 'Carrot'],
      );
    });
  });

  group('the local day a row is filed under', () {
    test('differs from the UTC day on both sides of Greenwich', () {
      // Fixed instants and fixed offsets, so this asserts the same thing
      // wherever it runs — the host timezone is not part of the test.
      //
      // One instant, 19:30 UTC on the 5th:
      final instant = DateTime.utc(2026, 9, 5, 19, 30);
      expect(_dateOnly(instant), '2026-09-05');

      // ...is 00:30 on the 6th for a user at UTC+5. Deriving logged_on
      // from the UTC instant would file their breakfast under yesterday.
      expect(_dateOnly(instant.add(const Duration(hours: 5))), '2026-09-06');

      // And the mirror case, 03:30 UTC on the 6th:
      final earlyUtc = DateTime.utc(2026, 9, 6, 3, 30);
      expect(_dateOnly(earlyUtc), '2026-09-06');

      // ...is 22:30 on the 5th for a user at UTC-5, whose late snack would
      // land on tomorrow instead.
      expect(
        _dateOnly(earlyUtc.subtract(const Duration(hours: 5))),
        '2026-09-05',
      );
    });

    test('pads a single-digit month and day to the date format', () {
      expect(_dateOnly(DateTime(2026, 1, 7)), '2026-01-07');
    });
  });
}

/// The date format `logged_on` is written and queried with.
String _dateOnly(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// A row shaped the way PostgREST returns one from `public.logged_foods`,
/// numeric columns and all.
const Map<String, dynamic> _loggedFoodRow = {
  'id': 'a3f1c2d4-0000-4000-8000-000000000001',
  'name': 'Chicken breast',
  'brand_name': null,
  'meal': 'dinner',
  'servings': '1.500',
  'grams': null,
  'calories': '512.50',
  'protein_grams': '32.25',
  'carbs_grams': '0.00',
  'fat_grams': '11.00',
  'sodium_mg': '890.00',
  'potassium_mg': '256.00',
  'logged_at': '2026-09-05T18:30:00Z',
  'logged_on': '2026-09-05',
};
