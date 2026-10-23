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
      .map(ShoppingIngredient.fromRecipe)
      .where((i) => i.name.isNotEmpty)
      .toList();
}
