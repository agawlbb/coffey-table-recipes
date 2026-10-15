import 'package:coffey_table_recipes/src/recipe_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'temperature display removes padding without rounding fractional digits',
    () {
      for (final (value, expected) in <(Object?, String)>[
        (350, '350'),
        (350.0, '350'),
        ('350.0000', '350'),
        ('350.5000', '350.5'),
        (65.125, '65.125'),
        ('65.1250', '65.125'),
        ('0.0000', '0'),
        ('-40.0000', '-40'),
        ('0.00000001', '0.00000001'),
        ('177.7778', '177.7778'),
        (null, ''),
      ]) {
        expect(recipeValue(value), expected, reason: 'Stored value: $value');
      }
    },
  );

  test('converted temperatures retain all supplied precision', () {
    final celsius = (350 - 32) * 5 / 9;
    final fahrenheit = (100 * 9 / 5) + 32;
    expect(recipeValue(fahrenheit), '212');
    expect(recipeValue(celsius), celsius.toString());
    expect(double.parse(recipeValue(celsius)), celsius);
    // The API can supply converted values padded to four decimal places.
    expect(recipeValue('176.5000'), '176.5');
    expect(recipeValue('177.7778'), '177.7778');
  });
}
