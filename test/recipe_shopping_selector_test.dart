import 'package:coffey_table_recipes/src/recipe_shopping_selector.dart';
import 'package:flutter/material.dart';
import 'package:coffey_table_recipes/src/shopping_ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('adds only selected ingredients and closes', (tester) async {
    List<String>? added;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RecipeShoppingSelector(
                    ingredients: const [
                      ShoppingIngredient('Salt'),
                      ShoppingIngredient('Flour'),
                      ShoppingIngredient('Eggs'),
                    ],
                    onAdd: (names) async {
                      added = names;
                    },
                  ),
                ),
              ),
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Salt'));
    await tester.tap(find.text('Flour'));
    await tester.tap(find.text('Salt'));
    await tester.pump();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Flour')).selected,
      isTrue,
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(added, ['Flour']);
    expect(find.text('Open'), findsOneWidget);
    expect(find.byType(RecipeShoppingSelector), findsNothing);
  });

  testWidgets('keeps selection when saving fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeShoppingSelector(
          ingredients: const [ShoppingIngredient('Eggs')],
          onAdd: (_) async => throw Exception('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eggs'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeShoppingSelector), findsOneWidget);
    expect(tester.widget<ListTile>(find.byType(ListTile)).selected, isTrue);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'shows duplicate warning only while selected and keeps details outside control',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeShoppingSelector(
            ingredients: const [
              ShoppingIngredient('Onion', details: '2 · Optional'),
            ],
            loadExisting: () async => ['Onions, diced'],
            onAdd: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Already on shopping list:'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('2 · Optional'),
        ),
        findsNothing,
      );
      expect(find.text('2 · Optional'), findsOneWidget);
      await tester.tap(find.text('Onion'));
      await tester.pump();
      expect(
        find.text('Already on shopping list: Onions, diced'),
        findsOneWidget,
      );
      await tester.tap(find.text('Onion'));
      await tester.pump();
      expect(find.textContaining('Already on shopping list:'), findsNothing);
    },
  );
}
