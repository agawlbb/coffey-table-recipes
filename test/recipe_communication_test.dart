import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('temporary refresh failure keeps loaded recipe visible', (
    tester,
  ) async {
    var fail = false;
    offlineStatus.value = false;
    addTearDown(() => offlineStatus.value = false);
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '1',
          recipeId: '1',
          title: 'Soup',
          request: (_) async {
            if (fail) throw ApiException(503, 'Temporary server failure');
            return {
              'recipe': {
                'id': '1',
                'title': 'Soup',
                'description': 'Keep this recipe readable.',
              },
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep this recipe readable.'), findsOneWidget);
    fail = true;
    offlineStatus.value = true;
    offlineStatus.value = false;
    await tester.pump();
    expect(find.text('Keep this recipe readable.'), findsOneWidget);
    expect(find.text('Temporary server failure'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
