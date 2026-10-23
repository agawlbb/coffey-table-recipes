import 'meal_plan_actions.dart';

import 'shopping_ingredient.dart';

/// Sum only explicit compatible quantities. Never infer amounts or densities.
List<ShoppingIngredient> mealPlanIngredients(List<Map<String, dynamic>> rows) {
  const units = {
    'cups': 'cup',
    'teaspoons': 'tsp',
    'teaspoon': 'tsp',
    'tablespoons': 'tbsp',
    'tablespoon': 'tbsp',
    'grams': 'g',
    'gram': 'g',
    'kilograms': 'kg',
    'kilogram': 'kg',
    'ounces': 'oz',
    'ounce': 'oz',
    'pounds': 'lb',
    'pound': 'lb',
    'lbs': 'lb',
    'milliliters': 'ml',
    'milliliter': 'ml',
    'liters': 'l',
    'liter': 'l',
  };
  final combined = <String, Map<String, dynamic>>{};
  final result = <Map<String, dynamic>>[];
  for (final row in rows) {
    final name = '${row['ingredient_name'] ?? ''}'.trim();
    final unit = '${row['unit_code'] ?? row['original_unit'] ?? ''}'
        .trim()
        .toLowerCase();
    final normalizedUnit = units[unit] ?? unit;
    final decimal = num.tryParse('${row['quantity_decimal']}');
    final numerator = num.tryParse('${row['quantity_numerator']}');
    final denominator = num.tryParse('${row['quantity_denominator']}');
    final amount =
        decimal ??
        (numerator != null && denominator != null && denominator > 0
            ? numerator / denominator
            : null);
    final canCombine =
        name.isNotEmpty &&
        amount != null &&
        amount.isFinite &&
        row['quantity_max_decimal'] == null &&
        ('${row['quantity_text'] ?? ''}'.trim().isEmpty ||
            RegExp(r'^[\d\s./¼½¾⅛⅜⅝⅞⅓⅔]+$')
                .hasMatch('${row['quantity_text']}'));
    final key =
        '${name.toLowerCase()}|$normalizedUnit|${row['preparation'] ?? ''}|${row['is_optional'] ?? false}';
    if (canCombine) {
      final existing = combined[key];
      if (existing != null) {
        existing['quantity_decimal'] = num.parse(
          ((existing['quantity_decimal'] as num) + amount).toStringAsPrecision(
            12,
          ),
        );
        continue;
      }
      final copy = Map<String, dynamic>.from(row)
        ..addAll({
          'quantity_decimal': amount,
          'quantity_numerator': null,
          'quantity_denominator': null,
          'quantity_text': null,
          'original_unit': normalizedUnit,
        });
      combined[key] = copy;
      result.add(copy);
    } else {
      result.add(Map<String, dynamic>.from(row));
    }
  }
  return result
      .map(_displayIngredient)
      .where((i) => i.name.isNotEmpty)
      .toList();
}

ShoppingIngredient _displayIngredient(Map<String, dynamic> row) {
  final copy = Map<String, dynamic>.from(row);
  final text = '${row['quantity_text'] ?? ''}'.trim();
  if (text.isEmpty || RegExp(r'^[\d\s./¼½¾⅛⅜⅝⅞⅓⅔]+$').hasMatch(text)) {
    final unit = '${row['unit_code'] ?? row['original_unit'] ?? ''}'
        .trim()
        .toLowerCase();
    final customary = {
      'cup',
      'cups',
      'tsp',
      'teaspoon',
      'teaspoons',
      'tbsp',
      'tablespoon',
      'tablespoons',
      'oz',
      'ounce',
      'ounces',
      'lb',
      'lbs',
      'pound',
      'pounds',
      'pt',
      'pint',
      'pints',
      'qt',
      'quart',
      'quarts',
      'gal',
      'gallon',
      'gallons',
      'fl oz',
    }.contains(unit);
    final decimal = num.tryParse('${row['quantity_decimal']}');
    final numerator = num.tryParse('${row['quantity_numerator']}');
    final denominator = num.tryParse('${row['quantity_denominator']}');
    final value =
        decimal ??
        (numerator != null && denominator != null && denominator > 0
            ? numerator / denominator
            : null);
    if (value != null && value.isFinite) {
      final maximum = num.tryParse('${row['quantity_max_decimal']}');
      copy['quantity_text'] =
          _quantity(value, customary) +
          (maximum != null && maximum.isFinite
              ? '–${_quantity(maximum, customary)}'
              : '');
    }
  }
  return ShoppingIngredient.fromRecipe(copy);
}

String _quantity(num value, bool customary) {
  if (customary && value >= 0 && value <= 1000000) {
    for (final denominator in [1, 2, 3, 4, 8, 16]) {
      final numerator = (value * denominator).round();
      if ((numerator / denominator - value).abs() > .00005) continue;
      final whole = numerator ~/ denominator,
          remainder = numerator % denominator;
      return remainder == 0
          ? '$whole'
          : '${whole == 0 ? '' : '$whole '}$remainder/$denominator';
    }
  }
  return value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Discover planned dates and fetch only occupied spans within server limits.
Future<List<ShoppingIngredient>> loadMealPlanIngredients(
  Future<Map<String, dynamic>> Function(String) request,
  String path,
  DateTime start,
  DateTime end,
) async {
  final from = mealPlanDate(start), to = mealPlanDate(end);
  final plan = await request('$path?from=$from&to=$to');
  final dates = <String>{
    for (final entry in (plan['entries'] as List? ?? []).cast<Map>())
      if (entry['kind'] == 'recipe' &&
          entry['plan_date'] is String &&
          (entry['plan_date'] as String).compareTo(from) >= 0 &&
          (entry['plan_date'] as String).compareTo(to) <= 0)
        entry['plan_date'] as String,
  }.toList()..sort();
  final rows = <Map<String, dynamic>>[];
  for (var index = 0; index < dates.length;) {
    final first = dates[index];
    final limit = DateTime.parse('${first}T00:00:00Z')
        .add(const Duration(days: 366));
    var last = first;
    while (index < dates.length &&
        !DateTime.parse('${dates[index]}T00:00:00Z').isAfter(limit)) {
      last = dates[index++];
    }
    final data = await request('$path/ingredients?from=$first&to=$last');
    rows.addAll(
      (data['ingredients'] as List? ?? []).map(
        (row) => Map<String, dynamic>.from(row as Map),
      ),
    );
  }
  return mealPlanIngredients(rows);
}
