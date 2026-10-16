import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> draft(int count) => {
  'id': '9',
  'revision': '1',
  'household_count': count,
  'title': 'Soup',
  'original_language': 'en',
  'measurement_system': 'metric',
  'ingredients': <Map<String, dynamic>>[],
  'steps': <Map<String, dynamic>>[],
  'actions': <Map<String, dynamic>>[],
  'photos': <Map<String, dynamic>>[],
  'groups': <Map<String, dynamic>>[],
  'tags': <Map<String, dynamic>>[],
  'pairings': <Map<String, dynamic>>[],
  'category_assignments': <Map<String, dynamic>>[],
};

void main() {
  testWidgets('shared save requires confirmation and cancel sends no write', (
    tester,
  ) async {
    var writes = 0;
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: draft(2),
          householdId: '2',
          save: (path, body) async {
            writes++;
            confirmed = body['confirm_shared_edit'] as bool?;
            return {'recipe': body};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.textContaining('every household'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save for all households'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(confirmed, isTrue);
  });
  testWidgets('sharing added during editing prompts before retry', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: draft(1),
          householdId: '1',
          save: (path, body) async {
            writes++;
            if (writes == 1) {
              throw ApiException(
                409,
                'Shared',
                code: 'shared_confirmation_required',
              );
            }
            expect(body['confirm_shared_edit'], isTrue);
            expect(body['title'], 'Soup');
            return {'recipe': body};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    await tester.tap(find.text('Save for all households'));
    await tester.pumpAndSettle();
    expect(writes, 2);
  });
}
