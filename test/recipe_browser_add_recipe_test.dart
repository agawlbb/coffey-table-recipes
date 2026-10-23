import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';

void main() {
  testWidgets(
    'Add recipe sits below search, invokes import and disables offline',
    (tester) async {
      var calls = 0;
      addTearDown(() => offlineStatus.value = false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecipeBrowser(
              householdId: '1',
              householdName: 'Table',
              request: (_) async => {'recipes': []},
              onAddRecipe: () => calls++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Add recipe')).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField)).dy),
      );
      await tester.tap(find.text('Add recipe'));
      expect(calls, 1);
      offlineStatus.value = true;
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Add recipe'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('meal selection mode hides Add recipe', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeBrowser(
            householdId: '1',
            householdName: 'Table',
            request: (_) async => {'recipes': []},
            onAddRecipe: () {},
            onSelect: (_) {},
            mealPlanDestination: 'Today',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add recipe'), findsNothing);
  });
}
