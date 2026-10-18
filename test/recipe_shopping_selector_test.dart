import 'package:coffey_table_recipes/src/recipe_shopping_selector.dart';
import 'package:flutter/material.dart';
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
                    ingredients: const ['Salt', 'Flour', 'Eggs'],
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
          ingredients: const ['Eggs'],
          onAdd: (_) async => throw Exception('offline'),
        ),
      ),
    );
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
}
