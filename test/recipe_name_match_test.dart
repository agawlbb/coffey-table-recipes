import 'package:coffey_table_recipes/src/recipe_name_match.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_editor_test.dart' show recipe;

void main() {
  test('matches duplicates, punctuation, reordered words and small typos', () {
    for (final pair in [
      [' Soup ', 'SOUP'],
      ['Chicken-pot pie', 'Chicken pot pie'],
      ['Roasted garlic chicken', 'Garlic roasted chicken'],
      ['Chocolate cookies', 'Chocolate cookie'],
      ['Chicken casserole', 'Chiken casserole'],
    ]) {
      expect(similarRecipeNames(pair[0], pair[1]), isTrue, reason: '$pair');
    }
    for (final pair in [
      ['', 'Soup'],
      ['Rice', 'Ribs'],
      ['Chicken soup', 'Chicken salad'],
      ['Tomato soup', 'Potato soup'],
      ['魚', '肉'],
    ]) {
      expect(similarRecipeNames(pair[0], pair[1]), isFalse, reason: '$pair');
    }
  });

  testWidgets('import warns immediately and edited title is checked on save', (
    tester,
  ) async {
    final draft = recipe()..remove('id');
    draft['edit_options'] = {
      'recipes': [
        {'id': '1', 'title': 'Soup'},
        {'id': '2', 'title': 'Chocolate cookies'},
      ],
    };
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: draft,
          householdId: '1',
          save: (_, body) async {
            saves++;
            return {
              'recipe': {...body, 'id': '3'},
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Similar recipe already exists'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Review recipe'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, 'Soup');
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Chocolate cookie');
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Similar recipe already exists'), findsOneWidget);
    expect(saves, 0);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();
    expect(saves, 1);
  });
}
