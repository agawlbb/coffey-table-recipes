import 'ingredient_amount.dart';
import 'recipe_name_match.dart';

class ShoppingIngredient {
  const ShoppingIngredient(this.name, {this.details = ''});
  final String name;
  final String details;

  factory ShoppingIngredient.fromRecipe(Map<String, dynamic> row) {
    final fields = ingredientEditingFields(row);
    var name = '${fields['name'] ?? ''}'.trim();
    if (name.isEmpty) {
      name = '${row['original_text'] ?? ''}'.trim();
      for (final key in ['amount', 'unit']) {
        final prefix = '${fields[key] ?? ''}'.trim();
        if (prefix.isNotEmpty &&
            name.toLowerCase().startsWith('${prefix.toLowerCase()} ')) {
          name = name.substring(prefix.length).trim();
        }
      }
    }
    final notes = <String>[];
    name = name.replaceAllMapped(RegExp(r'\([^)]*\)'), (m) {
      notes.add(m[0]!.substring(1, m[0]!.length - 1));
      return '';
    });
    final parts = name.split(',');
    name = parts.first
        .replaceAll(RegExp(r'\boptional\b', caseSensitive: false), '')
        .trim();
    notes.addAll(parts.skip(1).map((s) => s.trim()));
    final optional = row['is_optional'];
    return ShoppingIngredient(
      name,
      details: <String>{
        [
          fields['amount'],
          fields['unit'],
        ].where((s) => s != null && '$s'.trim().isNotEmpty).join(' '),
        '${fields['preparation'] ?? ''}'.trim(),
        ...notes,
        if (optional == true || optional == 1 || optional == '1') 'Optional',
      }.where((s) => s.isNotEmpty).join(' · '),
    );
  }
}

bool similarShoppingIngredients(String first, String second) {
  String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .split(',')
      .first
      .replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where(
        (word) =>
            word.isNotEmpty &&
            !{
              'a',
              'an',
              'of',
              'cup',
              'cups',
              'tbsp',
              'tsp',
              'teaspoon',
              'teaspoons',
              'tablespoon',
              'tablespoons',
              'g',
              'kg',
              'oz',
              'lb',
              'lbs',
              'ml',
              'pound',
              'pounds',
              'ounce',
              'ounces',
              'gram',
              'grams',
              'optional',
              'fresh',
              'chopped',
              'diced',
              'sliced',
              'minced',
            }.contains(word),
      )
      .map(
        (word) => word.endsWith('ies') && word.length > 4
            ? '${word.substring(0, word.length - 3)}y'
            : word.endsWith('oes')
            ? word.substring(0, word.length - 2)
            : word.endsWith('s') && !word.endsWith('ss') && word.length > 3
            ? word.substring(0, word.length - 1)
            : word,
      )
      .join(' ');
  final a = normalize(first), b = normalize(second);
  if (a.isEmpty || b.isEmpty) return false;
  if (similarRecipeNames(a, b)) return true;
  final wordsA = a.split(' ').toSet(), wordsB = b.split(' ').toSet();
  final overlap = wordsA.intersection(wordsB).length;
  return overlap > 0 &&
      overlap / wordsA.length >= .75 &&
      overlap / wordsB.length >= .75;
}
