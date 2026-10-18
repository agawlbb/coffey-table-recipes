import 'package:coffey_table_recipes/src/shopping_ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'separates shopping name from amount, preparation and optional notes',
    () {
      final ingredient = ShoppingIngredient.fromRecipe({
        'ingredient_name': 'onions (optional)',
        'quantity_text': '2',
        'preparation': 'finely chopped',
        'is_optional': true,
      });
      expect(ingredient.name, 'onions');
      expect(ingredient.details, contains('2'));
      expect(ingredient.details, contains('finely chopped'));
      expect(ingredient.details, contains('Optional'));
    },
  );
  test('matches plural, quantity, punctuation, reordered words and typos', () {
    expect(similarShoppingIngredients('Onion', '2 onions, diced'), isTrue);
    expect(similarShoppingIngredients('Tomato', 'Tomatoes'), isTrue);
    expect(similarShoppingIngredients('olive oil', 'Oil, olive'), isFalse);
    expect(similarShoppingIngredients('olive oil', 'oil olive'), isTrue);
    expect(similarShoppingIngredients('mozzarella', 'mozarella'), isTrue);
    expect(similarShoppingIngredients('rice', 'ribs'), isFalse);
    expect(similarShoppingIngredients('baking powder', 'baking soda'), isFalse);
    expect(similarShoppingIngredients('cream cheese', 'cream'), isFalse);
  });
}
