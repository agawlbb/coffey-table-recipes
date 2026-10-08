import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('browse searches the household and opens structured details', (tester) async {
    final paths = <String>[];
    Future<Map<String, dynamic>> request(String path) async {
      paths.add(path);
      if (path.contains('/recipes/9')) {
        return {'recipe': {
          'id': '9', 'title': 'Crêpes', 'original_language': 'fr',
          'servings': '4.0000', 'revision': '1',
          'ingredients': [{'group_id': null, 'original_text': '250 g de farine'}],
          'steps': [{'id': '4', 'position': 1, 'instruction': 'Préchauffer à 180°C.'}],
          'actions': [{'step_id': '4', 'temperature_value': '180.0000', 'temperature_unit': 'C'}],
          'source_title': 'Family recipe', 'groups': [], 'tags': [], 'photos': [], 'related': [], 'pairings': [],
        }};
      }
      return {'recipes': [{'id': '9', 'title': 'Crêpes', 'servings': '4.0000'}], 'next_offset': null};
    }
    await tester.pumpWidget(MaterialApp(home: RecipeBrowser(householdId: '2', householdName: 'Coffey', request: request)));
    await tester.pumpAndSettle();
    expect(find.text('Crêpes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'farine');
    await tester.tap(find.byTooltip('Search recipes'));
    await tester.pumpAndSettle();
    expect(paths.last, '/households/2/recipes?q=farine&offset=0');
    await tester.tap(find.text('Crêpes'));
    await tester.pumpAndSettle();
    expect(paths.last, '/households/2/recipes/9');
    expect(find.text('• 250 g de farine'), findsOneWidget);
    expect(find.text('1. Préchauffer à 180°C.'), findsOneWidget);
    expect(find.text('180°C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('display removes decimal padding without changing quantities', () {
    expect(recipeValue('1.25000000'), '1.25');
    expect(recipeValue('180.0000'), '180');
    expect(recipeValue('0.00000001'), '0.00000001');
  });
}
