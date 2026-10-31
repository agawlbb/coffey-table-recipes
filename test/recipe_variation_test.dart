import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> variationDraft([List<String> questions = const []]) => {
  'questions': questions,
  'change_description': 'Replaced cream with oat milk and reduced simmering to keep the soup smooth.',
  'recipe': {
    'title': 'Dairy-free soup',
    'original_language': 'en',
    'measurement_system': 'unspecified',
    'parent_recipe_id': '10',
    'import_key': 'stable-variation-key',
    'source_type': 'ai_variation',
    'ingredients': [
      {'id': 'new-i', 'original_text': 'Water', 'ingredient_name': 'water'},
    ],
    'steps': [
      {'id': 'new-s', 'instruction': 'Boil'},
    ],
    'tags': [
      {'kind': 'category', 'label': 'Variation'},
    ],
  },
};

void main() {
  setUp(() => offlineStatus.value = false);
  tearDown(() => offlineStatus.value = false);

  testWidgets('editing a saved variation preserves its machine source type', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: {
            ...(variationDraft()['recipe'] as Map<String, dynamic>),
            'id': '11',
          },
          householdId: '2',
          save: (path, body) async {
            expect(path, '/households/2/recipes/11');
            saved = body;
            return {'recipe': body};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(saved?['source_type'], 'ai_variation');
  });

  test('family relationships distinguish parent, sibling, and child', () {
    final recipe = {'id': '11', 'parent_recipe_id': '10'};
    expect(recipeRelationshipLabel(recipe, {'id': '10'}), 'Parent recipe');
    expect(
      recipeRelationshipLabel(recipe, {'id': '12', 'parent_recipe_id': '10'}),
      'Sibling variation',
    );
    expect(
      recipeRelationshipLabel(recipe, {'id': '13', 'parent_recipe_id': '11'}),
      'Child variation',
    );
    expect(
      recipeRelationshipLabel(recipe, {'id': '14', 'relationship': 'sibling'}),
      'Sibling variation',
    );
  });

  testWidgets(
    'compact title menu opens on tap and navigates the variation family',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paths = <String>[];
      final recipe = {
        ...(variationDraft()['recipe'] as Map<String, dynamic>),
        'id': '11',
        'variation_family': [
          {'id': '11', 'title': 'Dairy-free soup'},
          {'id': '10', 'title': 'Original soup', 'relationship': 'parent'},
          {'id': '12', 'title': 'Spicy soup', 'relationship': 'sibling'},
          {'id': '13', 'title': 'Slow cooker soup', 'relationship': 'child'},
          {'id': '14', 'title': 'Slow cooker ginger soup'},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '2',
            recipeId: '11',
            title: 'Dairy-free soup',
            request: (path) async {
              paths.add(path);
              if (path.endsWith('/11')) return {'recipe': recipe};
              return {
                'recipe': {
                  ...recipe,
                  'id': path.split('/').last,
                  'title': 'Opened relative',
                  'in_household': false,
                  'variation_family': [],
                },
              };
            },
            save: (_, _) async => variationDraft(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Request variation'), findsOneWidget);
      expect(find.text('Variation'), findsOneWidget);
      for (final entry in [
        ('Original soup', '10', 'Parent recipe'),
        ('Spicy soup', '12', 'Sibling variation'),
        ('Slow cooker soup', '13', 'Child variation'),
        ('Slow cooker ginger soup', '14', 'Family variation'),
      ]) {
        expect(find.text('Variations'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byTooltip('Edit recipe')).dx,
          closeTo(28, 0.1),
        );
        expect(
          tester.getTopRight(find.byType(PopupMenuButton<String>)).dx,
          closeTo(376, 0.1),
        );
        expect(
          tester.getTopRight(find.byTooltip('Delete recipe')).dx,
          lessThan(tester.getTopLeft(find.byType(PopupMenuButton<String>)).dx),
        );
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text('Dairy-free soup'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Dairy-free soup'),
          ),
          findsOneWidget,
        );
        expect(
          tester.getCenter(find.byType(PopupMenuButton<String>)).dy,
          closeTo(tester.getCenter(find.byTooltip('Edit recipe')).dy, 0.1),
        );
        expect(
          tester.getTopLeft(find.byType(PopupMenuButton<String>)).dy,
          lessThan(tester.getTopLeft(find.text('Start cooking')).dy),
        );
        expect(find.text('Recipe family'), findsNothing);
        expect(find.text(entry.$1), findsNothing);
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.$1).last);
        await tester.pumpAndSettle();
        expect(paths, contains('/households/2/recipes/${entry.$2}'));
        expect(find.text('Variations'), findsNothing);
        expect(find.text('Add to my household'), findsOneWidget);
        expect(find.byTooltip('Edit recipe'), findsNothing);
        expect(find.byTooltip('Delete recipe'), findsNothing);
        expect(find.text('Request variation'), findsNothing);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
