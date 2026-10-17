import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:coffey_table_recipes/src/recipe_import.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> blank() => {
  'id': '9',
  'revision': '2',
  'title': 'Birthday cake',
  'source_type': 'blank',
  'original_language': 'en',
  'measurement_system': 'unspecified',
  'ingredients': [],
  'steps': [],
  'groups': [],
  'actions': [],
  'photos': [],
  'tags': [],
  'pairings': [],
  'category_assignments': [
    {'category_id': '1'},
  ],
  'edit_options': {
    'categories': [
      {'id': '1', 'label': 'Desserts'},
    ],
  },
};

void main() {
  testWidgets('blank creation bypasses AI and requires category', (
    tester,
  ) async {
    final paths = <String>[];
    final recipe = blank()..remove('id');
    recipe['category_assignments'] = [];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeImport(
          householdId: '2',
          request: (path, body) async {
            paths.add(path);
            return {'recipe': recipe};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blank recipe'));
    await tester.pumpAndSettle();
    expect(paths, ['/households/2/recipe-blank']);
    expect(find.text('Favorite this recipe'), findsOneWidget);
    expect(find.text('Ingredients'), findsNothing);
    expect(find.text('Generate an image with AI'), findsNothing);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one category.'), findsOneWidget);
    expect(paths.length, 1);
  });

  testWidgets('saving blank preserves marker and skips category AI', (
    tester,
  ) async {
    final paths = <String>[];
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: blank(),
          householdId: '2',
          save: (path, body) async {
            paths.add(path);
            submitted = Map.from(body);
            return {'recipe': body};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(submitted?['source_type'], 'blank');
    expect(paths, ['/households/2/recipes/9']);
  });

  testWidgets('import review updates blank ID and revision', (tester) async {
    Map<String, dynamic>? submitted;
    String? savedPath;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeImport(
          householdId: '2',
          blankRecipe: blank(),
          request: (path, body) async {
            if (path.endsWith('/recipe-import')) {
              return {
                'questions': <String>[],
                'recipe': {
                  'title': 'Imported cake',
                  'source_type': 'ai_text',
                  'original_language': 'en',
                  'measurement_system': 'unspecified',
                  'ingredients': [
                    {
                      'id': 'new-i',
                      'ingredient_name': 'flour',
                      'original_text': '1 cup flour',
                    },
                  ],
                  'steps': [
                    {'id': 'new-s', 'instruction': 'Mix and bake.'},
                  ],
                  'edit_options': blank()['edit_options'],
                },
              };
            }
            savedPath = path;
            submitted = Map<String, dynamic>.from(body);
            throw ApiException(500, 'Retain review');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mix flour and bake.');
    await tester.ensureVisible(find.text('Prepare recipe'));
    await tester.tap(find.text('Prepare recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(savedPath, '/households/2/recipes/9');
    expect(submitted?['revision'], '2');
    expect(submitted?['source_type'], isNot('blank'));
    expect(
      (submitted?['category_assignments'] as List).first['category_id'],
      '1',
    );
    expect(find.textContaining('Retain review'), findsWidgets);
  });

  testWidgets(
    'blank detail uses existing controls and offers import without share',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '2',
            recipeId: '9',
            title: 'Cake',
            request: (path) async => path.endsWith('/favorites')
                ? {'people': [], 'current_person_id': null}
                : {'recipe': blank()},
            save: (path, body) async => throw ApiException(500, 'Not called'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Share recipe'), findsNothing);
      expect(find.byTooltip('Delete recipe'), findsOneWidget);
      expect(find.byTooltip('Favorite (hold for household)'), findsOneWidget);
      expect(find.text('Request variation'), findsNothing);
      await tester.tap(find.text('Import recipe'));
      await tester.pumpAndSettle();
      for (final name in ['Text', 'Website', 'File', 'Camera']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Blank recipe'), findsNothing);
    },
  );
}
