import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/food_models.dart';

/// Anything the Nutritionix API refused or could not answer, already
/// phrased for a StatusCard.
class NutritionixException implements Exception {
  const NutritionixException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The food database behind the logger.
///
/// Three endpoints, all on API v2:
///   * `/search/instant` — the type-ahead list, nutrients not included.
///   * `/natural/nutrients` — one food, resolved to actual numbers.
///   * `/search/item` — the same, addressed by barcode.
///
/// Takes its http.Client rather than making one, so tests can hand it a
/// `MockClient` and the app can share a single connection pool.
class NutritionixService {
  NutritionixService({
    required http.Client httpClient,
    this.appId = defaultAppId,
    this.appKey = defaultAppKey,
  }) : _http = httpClient;

  static const String _apiRoot = 'https://trackapi.nutritionix.com/v2';

  /// Placeholders by default, overridable per build with
  /// `--dart-define=NUTRITIONIX_APP_ID=…`. The same split
  /// MiloCredentials uses for the Groq and Gemini keys: a development
  /// build can carry its keys in the build command, and nothing that could
  /// be committed holds a real one.
  static const String defaultAppId = String.fromEnvironment(
    'NUTRITIONIX_APP_ID',
    defaultValue: 'YOUR_NUTRITIONIX_APP_ID',
  );

  static const String defaultAppKey = String.fromEnvironment(
    'NUTRITIONIX_APP_KEY',
    defaultValue: 'YOUR_NUTRITIONIX_APP_KEY',
  );

  static const String keysMissingMessage =
      'Nutritionix keys are not set. Rebuild with '
      '--dart-define=NUTRITIONIX_APP_ID=… --dart-define=NUTRITIONIX_APP_KEY=…';

  /// Attribute ids in `full_nutrients`, used as the fallback when the
  /// top-level `nf_` field is null.
  static const int _attrSodium = 307;
  static const int _attrPotassium = 306;

  final http.Client _http;

  /// Taken from the build unless a caller overrides them, which is how a
  /// test exercises the endpoints without the build carrying keys.
  final String appId;
  final String appKey;

  /// False while the placeholders are still in place, which is what the
  /// search screen checks before it offers to call anything.
  bool get isConfigured =>
      !appId.startsWith('YOUR_') && !appKey.startsWith('YOUR_');

  Map<String, String> get _headers => {
        'x-app-id': appId,
        'x-app-key': appKey,
        // Required even on the free tier. '0' is the documented value for
        // a single-user app that does not model its own accounts.
        'x-remote-user-id': '0',
      };

  /// The type-ahead list for [query], common foods first then branded.
  ///
  /// Returns an empty list rather than throwing on a blank query, so the
  /// search field can call this unconditionally.
  Future<List<FoodSearchHit>> searchFoods(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    _requireKeys();

    final uri = Uri.parse('$_apiRoot/search/instant').replace(
      queryParameters: {
        'query': trimmed,
        'branded': 'true',
        'common': 'true',
      },
    );

    final body = await _get(uri, notFoundMessage: 'Nothing matched "$trimmed".');

    return [
      ..._hits(body['common'], isBranded: false),
      ..._hits(body['branded'], isBranded: true),
    ];
  }

  /// Resolves [foodName] to actual nutrients.
  ///
  /// The endpoint is a natural-language one — "2 eggs and toast" parses to
  /// two foods — but the logger asks about one food at a time and takes the
  /// first result, since the configurator handles the quantity itself.
  Future<FoodItem> getFoodDetails(String foodName) async {
    _requireKeys();

    final response = await _http.post(
      Uri.parse('$_apiRoot/natural/nutrients'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'query': foodName}),
    );

    return _firstFood(
      response,
      notFoundMessage: 'Nutritionix has no nutrition data for "$foodName".',
    );
  }

  /// Resolves a scanned barcode straight to nutrients.
  Future<FoodItem> getFoodByBarcode(String upc) async {
    final trimmed = upc.trim();
    if (trimmed.isEmpty) {
      throw const NutritionixException('Enter a barcode number first.');
    }
    _requireKeys();

    final response = await _http.get(
      Uri.parse('$_apiRoot/search/item').replace(
        queryParameters: {'upc': trimmed},
      ),
      headers: _headers,
    );

    return _firstFood(
      response,
      notFoundMessage: 'No food in the database carries the barcode $trimmed.',
    );
  }

  void _requireKeys() {
    if (!isConfigured) throw const NutritionixException(keysMissingMessage);
  }

  Future<Map<String, dynamic>> _get(
    Uri uri, {
    required String notFoundMessage,
  }) async {
    final response = await _http.get(uri, headers: _headers);
    return _decode(response, notFoundMessage: notFoundMessage);
  }

  Map<String, dynamic> _decode(
    http.Response response, {
    required String notFoundMessage,
  }) {
    if (response.statusCode != 200) {
      throw NutritionixException(
        _failureMessage(response.statusCode, response.body, notFoundMessage),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const NutritionixException(
        'Nutritionix returned a response this app could not read.',
      );
    }
    return decoded;
  }

  /// Both nutrient endpoints answer with a `foods` array; the logger uses
  /// the first entry.
  FoodItem _firstFood(
    http.Response response, {
    required String notFoundMessage,
  }) {
    final body = _decode(response, notFoundMessage: notFoundMessage);
    final foods = body['foods'];
    if (foods is! List || foods.isEmpty) {
      throw NutritionixException(notFoundMessage);
    }
    return _parseFood(foods.first as Map<String, dynamic>);
  }

  List<FoodSearchHit> _hits(dynamic raw, {required bool isBranded}) {
    if (raw is! List) return const [];

    return raw.whereType<Map<String, dynamic>>().map((food) {
      final quantity = _number(food['serving_qty']);
      final unit = food['serving_unit'];

      return FoodSearchHit(
        name: (food['food_name'] as String?) ?? 'Unnamed food',
        isBranded: isBranded,
        brandName: food['brand_name'] as String?,
        thumbUrl: _photo(food['photo'], 'thumb'),
        servingPreview: quantity == null || unit is! String
            ? null
            : '${formatAmount(quantity)} $unit',
        // Only branded hits carry a calorie count; a common one has to be
        // resolved through /natural/nutrients first.
        caloriesPreview: _number(food['nf_calories']),
        upc: food['upc'] as String?,
      );
    }).toList();
  }

  FoodItem _parseFood(Map<String, dynamic> food) {
    final fullNutrients = food['full_nutrients'];

    return FoodItem(
      name: (food['food_name'] as String?) ?? 'Unnamed food',
      brandName: food['brand_name'] as String?,
      perServing: NutritionTotals(
        calories: _number(food['nf_calories']) ?? 0,
        protein: _number(food['nf_protein']) ?? 0,
        carbs: _number(food['nf_total_carbohydrate']) ?? 0,
        fat: _number(food['nf_total_fat']) ?? 0,
        // Sodium and potassium are the two the top-level fields most often
        // omit — /natural/nutrients regularly answers with a null
        // nf_potassium while still carrying the value in full_nutrients.
        // Without this fallback the micronutrient rows would read 0 mg for
        // most foods.
        sodium: _number(food['nf_sodium']) ??
            _fromFullNutrients(fullNutrients, _attrSodium) ??
            0,
        potassium: _number(food['nf_potassium']) ??
            _fromFullNutrients(fullNutrients, _attrPotassium) ??
            0,
      ),
      servingQty: _number(food['serving_qty']) ?? 1,
      servingUnit: (food['serving_unit'] as String?) ?? 'serving',
      servingWeightGrams: _number(food['serving_weight_grams']),
      thumbUrl: _photo(food['photo'], 'thumb'),
      highresUrl: _photo(food['photo'], 'highres') ??
          _photo(food['photo'], 'thumb'),
      upc: food['upc'] as String?,
    );
  }

  double? _fromFullNutrients(dynamic raw, int attrId) {
    if (raw is! List) return null;
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      if (_number(entry['attr_id'])?.toInt() == attrId) {
        return _number(entry['value']);
      }
    }
    return null;
  }

  String? _photo(dynamic raw, String key) {
    if (raw is! Map<String, dynamic>) return null;
    final url = raw[key];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// The API returns ints and doubles interchangeably for the same field,
  /// and null for a nutrient it has no value for, so every numeric read
  /// goes through here rather than a cast that would throw on real data.
  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _failureMessage(int status, String body, String notFoundMessage) {
    switch (status) {
      case 401:
      case 403:
        return 'Nutritionix rejected the credentials. Check the app id and '
            'key this build was compiled with.';
      case 404:
        return notFoundMessage;
      case 409:
        // What the barcode endpoint answers with for an unknown UPC.
        return notFoundMessage;
      case 429:
        return 'Nutritionix is rate limiting this key. Try again shortly.';
      default:
        final detail = _errorDetail(body);
        return 'Nutritionix returned $status${detail == null ? '.' : ': $detail'}';
    }
  }

  String? _errorDetail(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } on FormatException {
      // Not JSON — fall through to the raw body.
    }
    return body;
  }
}
