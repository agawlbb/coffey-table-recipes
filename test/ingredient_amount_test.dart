import 'package:coffey_table_recipes/src/ingredient_amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('natural fractions and decimals produce exclusive exact quantities', () {
    final row = <String, dynamic>{
      'quantity_decimal': 7,
      'quantity_numerator': 9,
      'quantity_denominator': 2,
    };
    applyIngredientFields(row, '1 1/2', 'cups', 'flour', 'sifted');
    expect(row['original_text'], '1 1/2 cups flour, sifted');
    expect(row['quantity_decimal'], isNull);
    expect(row['quantity_numerator'], 3);
    expect(row['quantity_denominator'], 2);
    applyIngredientFields(row, '.25', 'cup', 'sugar', '');
    expect(row['quantity_decimal'], .25);
    expect(row['quantity_numerator'], isNull);
    expect(row['quantity_denominator'], isNull);
    expect(ingredientAmount('2½')['quantity_numerator'], 5);
    expect(() => ingredientAmount('1/0'), throwsFormatException);
  });
  test(
    'free amounts and compound measures remain text without guessed scaling',
    () {
      for (final text in [
        'to taste',
        'as needed',
        '1 cup plus 2 tablespoons',
      ]) {
        final row = ingredientAmount(text);
        expect(row['quantity_text'], text);
        expect(row['quantity_decimal'], isNull);
        expect(row['quantity_numerator'], isNull);
      }
      expect(ingredientAmount('1–2')['quantity_max_decimal'], 2);
      expect(() => ingredientAmount('2–1'), throwsFormatException);
    },
  );
  test('legacy amounts containing units do not duplicate those units', () {
    expect(
      ingredientEditingFields({
        'quantity_text': '2 cups',
        'original_unit': 'cups',
        'ingredient_name': 'milk',
      })['amount'],
      '2',
    );
    final fields = ingredientEditingFields({
      'original_text': '1 1/2 cups flour',
      'ingredient_name': 'flour',
    });
    expect(fields['amount'], '1 1/2');
    expect(fields['unit'], 'cups');
  });
}
