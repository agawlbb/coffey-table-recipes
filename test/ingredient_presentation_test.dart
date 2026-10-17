import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:coffey_table_recipes/src/cooking_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture() => {
  'title': 'Grouped recipe',
  'original_language': 'en',
  'measurement_system': 'us',
  'groups': [
    {'id': 'g', 'title': 'Sauce'},
  ],
  'ingredients': [
    {'id': 'a', 'original_text': 'Water', 'ingredient_name': 'Water'},
    {
      'id': 'b',
      'group_id': 'g',
      'original_text': 'Tomatoes',
      'ingredient_name': 'Tomatoes',
    },
  ],
  'steps': [
    {'id': 's', 'instruction': 'Mix.'},
  ],
};

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('coffey_table_recipes/timers'),
          (call) async => call.method == 'list' ? [] : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('coffey_table_recipes/timers'),
          null,
        );
  });
  testWidgets(
    'visible ingredient delete removes only that row from the saved draft',
    (tester) async {
      Map<String, dynamic>? saved;
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeEditor(
            householdId: '2',
            recipe: fixture(),
            save: (_, body) async {
              saved = body;
              throw ApiException(500, 'Captured');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Go to ingredients'));
      await tester.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('Tomatoes'),
        matching: find.byType(ListTile),
      );
      final delete = find.descendant(
        of: row,
        matching: find.byTooltip('Delete ingredient'),
      );
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('Tomatoes'), findsNothing);
      expect(find.text('Water'), findsOneWidget);
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect((saved!['ingredients'] as List).single['id'], 'a');
      expect((saved!['groups'] as List).single['id'], 'g');
      expect(tester.takeException(), isNull);
    },
  );
  for (final cooking in [false, true]) {
    testWidgets(
      '${cooking ? 'cooking' : 'detail'} group labels are bold and members indented',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: cooking
                ? CookingMode(recipe: fixture())
                : RecipeDetail(
                    householdId: '2',
                    recipeId: '1',
                    title: 'Grouped recipe',
                    request: (_) async => {'recipe': fixture()},
                  ),
          ),
        );
        await tester.pumpAndSettle();
        if (cooking) {
          await tester.tap(find.text('View ingredients'));
          await tester.pumpAndSettle();
        }
        final group = find.text('Sauce');
        await tester.ensureVisible(group);
        expect(tester.widget<Text>(group).style!.fontWeight, FontWeight.bold);
        expect(
          tester.getTopLeft(find.text('• Tomatoes')).dx,
          closeTo(tester.getTopLeft(group).dx + 16, 0.1),
        );
        expect(
          tester.getTopLeft(find.text('• Water')).dx,
          closeTo(tester.getTopLeft(group).dx, 0.1),
        );
        expect(
          tester.getTopLeft(group).dy,
          lessThan(tester.getTopLeft(find.text('• Tomatoes')).dy),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
