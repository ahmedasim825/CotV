import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/food_models.dart';

/// Anything either food API refused or could not answer, already phrased
/// for a StatusCard.
class FoodApiException implements Exception {
  const FoodApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The two food databases behind the logger, behind one interface.
///
///   * **Open Food Facts** answers barcodes, and text searches that USDA
///     draws a blank on. Packaged products worldwide, no key.
///   * **USDA FoodData Central** answers searches. Generic ingredients
///     with proper micronutrients, plus branded entries.
///
/// Both quote nutrients per 100 g, which is why [FoodItem] is stored that
/// way and neither mapper has to invent a serving.
class FoodApiService {
  FoodApiService({
    required http.Client httpClient,
    this.usdaApiKey = defaultUsdaApiKey,
  }) : _http = httpClient;

  /// Open Food Facts needs no key and no account. What it asks instead is
  /// that every client identify itself, and it throttles or blocks
  /// anonymous traffic — so this header is the whole of our obligation to
  /// them. Their documented format is
  /// `AppName - Platform - Version (Contact: …)`.
  static const String userAgent =
      'CotVApp - Windows/iOS - Version 1.0 '
      '(Contact: ahmedasim825@gmail.com)';

  static const String _offRoot = 'https://world.openfoodfacts.org';

  static const String _usdaRoot = 'https://api.nal.usda.gov/fdc/v1';

  /// DEMO_KEY works without signup but is throttled to roughly 30
  /// requests an hour per IP, which a debounced search field exhausts
  /// quickly. A free key from api.data.gov lifts that; pass it as
  /// `--dart-define=USDA_API_KEY=…`.
  static const String defaultUsdaApiKey = String.fromEnvironment(
    'USDA_API_KEY',
    defaultValue: 'DEMO_KEY',
  );

  /// USDA nutrient ids.
  static const int _nutrientCalories = 1008;
  static const int _nutrientProtein = 1003;
  static const int _nutrientFat = 1004;
  static const int _nutrientCarbs = 1005;
  static const int _nutrientFiber = 1079;
  static const int _nutrientPotassium = 1092;
  static const int _nutrientSodium = 1093;

  /// The kilojoule Energy row. A food carries this *and* 1008, which is
  /// why calories are never read by nutrient name.
  static const int _nutrientKilojoules = 1062;

  /// The legacy nutrient *number* for Energy. A different field from
  /// `nutrientId` — it arrives as the string "208" in `nutrientNumber` —
  /// and some older records carry it where 1008 is absent.
  static const String _legacyEnergyNumber = '208';

  /// Thermochemical kilocalorie. 1 kcal = 4.184 kJ exactly.
  static const double _kjPerKcal = 4.184;

  /// Where each USDA data type sorts, lowest first.
  ///
  /// Foundation and SR Legacy are lab-analysed whole foods with the
  /// fullest micronutrient coverage, so they lead. Survey (FNDDS) entries
  /// are prepared-dish composites — useful, but less precise. Branded is
  /// last: it is requested so a packaged product with no barcode to hand
  /// is still findable, not because it is what a search for "broccoli"
  /// wants.
  static const Map<String, int> _dataTypeRank = {
    'Foundation': 0,
    'SR Legacy': 1,
    'Survey (FNDDS)': 2,
    'Branded': 3,
  };

  static const List<String> _requestedDataTypes = [
    'Foundation',
    'SR Legacy',
    'Survey (FNDDS)',
    'Branded',
  ];

  final http.Client _http;
  final String usdaApiKey;

  bool get isUsingDemoKey => usdaApiKey == 'DEMO_KEY';

  // -------------------------------------------------------------------
  // Barcodes — Open Food Facts
  // -------------------------------------------------------------------

  /// Resolves a scanned barcode against Open Food Facts.
  Future<FoodItem> getFoodByBarcode(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) {
      throw const FoodApiException('Enter a barcode number first.');
    }

    final notFound =
        'Open Food Facts has no product with the barcode $trimmed.';

    final response = await _http.get(
      Uri.parse('$_offRoot/api/v2/product/$trimmed.json'),
      headers: const {'User-Agent': userAgent},
    );

    if (response.statusCode == 404) throw FoodApiException(notFound);
    if (response.statusCode != 200) {
      throw FoodApiException(
        'Could not reach Open Food Facts (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FoodApiException(
        'Open Food Facts returned a response this app could not read.',
      );
    }

    // A code OFF does not know still comes back 200, with status 0 — so
    // this, not the HTTP status, is what decides a miss.
    if (_number(decoded['status'])?.toInt() != 1) {
      throw FoodApiException(notFound);
    }

    final product = decoded['product'];
    if (product is! Map<String, dynamic>) throw FoodApiException(notFound);

    return _foodFromOff(product, barcode: trimmed);
  }

  FoodItem _foodFromOff(
    Map<String, dynamic> product, {
    required String barcode,
  }) {
    final nutriments = product['nutriments'];
    final n = nutriments is Map<String, dynamic>
        ? nutriments
        : const <String, dynamic>{};

    return FoodItem(
      name: _firstString([
            product['product_name'],
            product['product_name_en'],
          ]) ??
          'Unnamed product',
      brandName: _firstBrand(product['brands']),
      source: FoodDataSource.openFoodFacts,
      per100g: NutritionTotals(
        calories: _number(n['energy-kcal_100g']) ??
            _number(n['energy-kcal_serving']) ??
            0,
        protein: _number(n['proteins_100g']) ?? 0,
        carbs: _number(n['carbohydrates_100g']) ?? 0,
        fat: _number(n['fat_100g']) ?? 0,
        // Already grams, unlike the two below.
        fiber: _number(n['fiber_100g']) ?? 0,
        // OFF normalises both of these to grams — sodium_unit and
        // potassium_unit read "g" — so they are 1000x off unless
        // converted. Read raw, a chocolate spread reports 0 mg of sodium.
        sodium: _milligrams(n['sodium_100g'] ?? n['sodium_value']),
        potassium: _milligrams(n['potassium_100g']),
      ),
      servingWeightGrams: _number(product['serving_quantity']),
      servingText: _firstString([product['serving_size']]),
      thumbUrl: _firstString([
        product['image_small_url'],
        product['image_front_url'],
      ]),
      highresUrl: _firstString([
        product['image_front_url'],
        product['image_small_url'],
      ]),
      barcode: barcode.isEmpty ? null : barcode,
    );
  }

  /// OFF quotes these in grams; the app stores milligrams.
  double _milligrams(dynamic grams) => (_number(grams) ?? 0) * 1000;

  // -------------------------------------------------------------------
  // Search — USDA, falling back to Open Food Facts
  // -------------------------------------------------------------------

  /// Searches USDA FoodData Central.
  ///
  /// Returns hits that already carry every nutrient: unlike the endpoint
  /// this replaced, the search response is complete, so tapping a row
  /// opens the configurator without a second round trip.
  Future<List<FoodSearchHit>> searchFoods(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final uri = Uri.parse('$_usdaRoot/foods/search').replace(
      queryParameters: {
        'query': trimmed,
        'api_key': usdaApiKey,
        'dataType': _requestedDataTypes.join(','),
        // Large enough that generic entries reach the page at all —
        // USDA's own ordering puts branded packages first, so a small
        // page can come back branded-only and leave the ranking nothing
        // to do.
        'pageSize': '25',
      },
    );

    final response = await _http.get(uri);
    final body = _decodeUsda(response);

    final foods = body['foods'];
    final hits = foods is List
        ? foods
            .whereType<Map<String, dynamic>>()
            // Some Foundation records come back with 70-odd nutrients and
            // no Energy row of any kind - not 1008, not 1062, not the
            // legacy 208. Energy for those lives only on the detail
            // endpoint. Keeping them would put a 0 kcal row at the very
            // top of the list, because generic entries are ranked first,
            // and logging one would add nothing to the day.
            .where(_usdaHasEnergy)
            .map(_hitFromUsda)
            .toList()
        : <FoodSearchHit>[];

    if (hits.isEmpty) return _searchOpenFoodFacts(trimmed);

    // USDA ranks branded packages above the generic cut, so "chicken
    // breast" returns supermarket chicken before chicken. Dart's sort is
    // not stable, so ties are broken by original index to keep USDA's own
    // relevance order within each group.
    final ordered = hits.indexed.toList()
      ..sort((a, b) {
        final byRank = a.$2.sortRank.compareTo(b.$2.sortRank);
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });

    return [for (final (_, hit) in ordered) hit];
  }

  FoodSearchHit _hitFromUsda(Map<String, dynamic> food) {
    final nutrients = food['foodNutrients'];
    final list = nutrients is List
        ? nutrients.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];

    final dataType = food['dataType'] as String?;

    return FoodSearchHit(
      isBranded: dataType == 'Branded',
      // An unrecognised data type sorts with Branded rather than ahead of
      // Foundation, so a new USDA category cannot quietly take over the
      // top of the list.
      sortRank: _dataTypeRank[dataType] ?? _dataTypeRank['Branded']!,
      item: FoodItem(
        name: (food['description'] as String?) ?? 'Unnamed food',
        brandName: _firstString([food['brandName'], food['brandOwner']]),
        source: FoodDataSource.usda,
        per100g: NutritionTotals(
          calories: _usdaCalories(list),
          protein: _usdaValue(list, _nutrientProtein) ?? 0,
          carbs: _usdaValue(list, _nutrientCarbs) ?? 0,
          fat: _usdaValue(list, _nutrientFat) ?? 0,
          fiber: _usdaValue(list, _nutrientFiber) ?? 0,
          sodium: _usdaValue(list, _nutrientSodium) ?? 0,
          potassium: _usdaValue(list, _nutrientPotassium) ?? 0,
        ),
        servingWeightGrams: _usdaServingGrams(food),
      ),
    );
  }

  /// Whether a search record carries any Energy row at all.
  ///
  /// Distinct from an energy row whose value is zero: water really is
  /// 0 kcal and belongs in the results, while a record with no energy row
  /// simply did not ship one in this payload.
  bool _usdaHasEnergy(Map<String, dynamic> food) {
    final nutrients = food['foodNutrients'];
    if (nutrients is! List) return false;

    for (final nutrient in nutrients.whereType<Map<String, dynamic>>()) {
      final id = _number(nutrient['nutrientId'])?.toInt();
      if (id == _nutrientCalories || id == _nutrientKilojoules) return true;
      if (nutrient['nutrientNumber']?.toString() == _legacyEnergyNumber) {
        return true;
      }
    }
    return false;
  }

  /// Pulls one nutrient out by id.
  ///
  /// Matching by id rather than by name is what keeps Energy honest: both
  /// the kJ row (1062) and the kcal row (1008) are named "Energy", and
  /// taking the first match by name reports a food at 4.184x its calories.
  double? _usdaValue(List<Map<String, dynamic>> nutrients, int nutrientId) {
    for (final nutrient in nutrients) {
      if (_number(nutrient['nutrientId'])?.toInt() == nutrientId) {
        return _number(nutrient['value']);
      }
    }
    return null;
  }

  /// Calories, down three fallbacks.
  ///
  /// Most records carry 1008 in kcal. Some older ones carry only the
  /// legacy nutrient *number* "208" — a different field from nutrientId.
  /// A few carry only the kilojoule row, which is worth converting rather
  /// than reporting a real food as 0 kcal.
  double _usdaCalories(List<Map<String, dynamic>> nutrients) {
    final kcal = _usdaValue(nutrients, _nutrientCalories);
    if (kcal != null && kcal > 0) return kcal;

    final legacy = _usdaLegacyValue(nutrients, _legacyEnergyNumber);
    if (legacy != null && legacy > 0) return legacy;

    final kilojoules = _usdaValue(nutrients, _nutrientKilojoules);
    if (kilojoules != null && kilojoules > 0) return kilojoules / _kjPerKcal;

    // Genuinely zero-calorie foods exist — water, black coffee — so a
    // zero that survived all three lookups is reported as zero.
    return kcal ?? legacy ?? 0;
  }

  /// Reads a nutrient by its legacy `nutrientNumber` string.
  double? _usdaLegacyValue(
    List<Map<String, dynamic>> nutrients,
    String nutrientNumber,
  ) {
    for (final nutrient in nutrients) {
      if (nutrient['nutrientNumber']?.toString() == nutrientNumber) {
        return _number(nutrient['value']);
      }
    }
    return null;
  }

  /// A serving weight only where USDA gives one in a mass unit. A
  /// `servingSizeUnit` of "ml" or "IU" is not grams, and treating it as
  /// grams would silently mis-scale every portion of that food.
  double? _usdaServingGrams(Map<String, dynamic> food) {
    final unit = (food['servingSizeUnit'] as String?)?.toLowerCase();
    if (unit != 'g' && unit != 'gram' && unit != 'grm') return null;
    return _number(food['servingSize']);
  }

  /// USDA is a US database, so a regional supermarket brand returns
  /// nothing from it. Open Food Facts is crowd-sourced and worldwide, and
  /// covers exactly that gap.
  ///
  /// This is the legacy CGI search — the only OFF text-search endpoint
  /// that is public and keyless — and it 503s intermittently under load.
  /// Every failure here returns an empty list instead of throwing: the
  /// user asked USDA a question that had no answer, and a flaky bonus
  /// lookup must not turn that into an error.
  Future<List<FoodSearchHit>> _searchOpenFoodFacts(String query) async {
    final uri = Uri.parse('$_offRoot/cgi/search.pl').replace(
      queryParameters: {
        'search_terms': query,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '20',
      },
    );

    try {
      final response =
          await _http.get(uri, headers: const {'User-Agent': userAgent});
      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];

      final products = decoded['products'];
      if (products is! List) return const [];

      return [
        for (final product in products.whereType<Map<String, dynamic>>())
          if (_hasUsableName(product))
            FoodSearchHit(
              isBranded: true,
              // Below every USDA data type, so a later USDA result can
              // never be pushed under a crowd-sourced one.
              sortRank: _dataTypeRank['Branded']! + 1,
              item: _foodFromOff(
                product,
                barcode: (product['code'] as String?) ?? '',
              ),
            ),
      ];
    } catch (_) {
      // Socket errors, timeouts, malformed bodies — all the same answer:
      // the primary search already found nothing.
      return const [];
    }
  }

  /// OFF products are user-submitted and some carry no name at all, which
  /// would render as a row of "Unnamed product".
  bool _hasUsableName(Map<String, dynamic> product) =>
      _firstString([product['product_name'], product['product_name_en']]) !=
      null;

  Map<String, dynamic> _decodeUsda(http.Response response) {
    switch (response.statusCode) {
      case 200:
        break;
      case 403:
        throw FoodApiException(
          isUsingDemoKey
              ? 'USDA rejected DEMO_KEY. It is shared and heavily throttled — '
                  'add a free key from api.data.gov as USDA_API_KEY.'
              : 'USDA rejected the USDA API key this build was compiled with.',
        );
      case 429:
        throw FoodApiException(
          isUsingDemoKey
              ? 'DEMO_KEY has hit its hourly limit (about 30 searches). Add a '
                  'free key from api.data.gov as USDA_API_KEY to lift it.'
              : 'USDA is rate limiting this key. Try again shortly.',
        );
      default:
        throw FoodApiException(
          'USDA FoodData Central returned ${response.statusCode}.',
        );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FoodApiException(
        'USDA returned a response this app could not read.',
      );
    }
    return decoded;
  }

  // -------------------------------------------------------------------

  String? _firstString(List<dynamic> candidates) {
    for (final value in candidates) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// `brands` is a comma-separated list ("Nutella, Ferrero, Yum yum"); the
  /// first entry is the one worth showing on a row.
  String? _firstBrand(dynamic brands) {
    if (brands is! String || brands.trim().isEmpty) return null;
    return brands.split(',').first.trim();
  }

  /// Both APIs return ints, doubles and occasionally numeric strings for
  /// the same field, and null for anything they have no value for.
  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
