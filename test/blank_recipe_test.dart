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
    'favorites': {
      'current_person_id': '10',
      'people': [
        {'id': '10', 'display_name': 'Alice', 'favorite': false},
        {'id': '11', 'display_name': 'Bob', 'favorite': false},
      ],
    },
    'categories': [
      {'id': '1', 'label': 'Desserts'},
    ],
  },
};

void main() {
  testWidgets('add recipe places blank last after all import choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeImport(householdId: '2', request: (_, body) async => {}),
      ),
    );
    await tester.pumpAndSettle();
    final choices = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(choices.map((chip) => (chip.label as Text).data).toList(), [
      'Text',
      'Website',
      'File',
      'Camera',
      'Blank recipe',
    ]);
  });

  for (final kind in ['text', 'website', 'file', 'camera']) {
    testWidgets('blank detail opens selected $kind import directly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '2',
            recipeId: '9',
            title: 'Cake',
            request: (path) async => path.endsWith('/favorites')
                ? {'people': []}
                : {'recipe': blank()},
            save: (_, body) async => {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final labels = {
        'text': 'Text',
        'website': 'Website',
        'file': 'File',
        'camera': 'Camera',
      };
      await tester.tap(find.text(labels[kind]!));
      await tester.pumpAndSettle();
      final importer = tester.widget<RecipeImport>(find.byType(RecipeImport));
      expect(importer.initialKind, kind);
      expect(importer.blankRecipe?['id'], '9');
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, labels[kind]!))
            .selected,
        isTrue,
      );
    });
  }

  testWidgets('blank creation saves an omitted category without confirmation', (
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
    expect(find.byTooltip('Favorite (hold for household)'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Ingredients'), findsNothing);
    expect(find.text('Generate an image with AI'), findsNothing);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(paths, ['/households/2/recipe-blank', '/households/2/recipes']);
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

  testWidgets('blank heart toggles own favorite and edits household choices', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final draft = blank()..remove('id');
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: draft,
          householdId: '2',
          save: (_, body) async {
            submitted = Map.from(body);
            throw ApiException(500, 'Keep draft');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final heart = find.byTooltip('Favorite (hold for household)');
    await tester.ensureVisible(heart);
    await tester.tap(heart);
    await tester.pumpAndSettle();
    expect(find.text('Favorite of Alice'), findsOneWidget);
    await tester.longPress(heart);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Favorite of Alice'), findsOneWidget);
    await tester.longPress(heart);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Favorite of Alice and Bob'), findsOneWidget);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(submitted?['favorite_people'], [
      {'person_id': '10', 'favorite': true},
      {'person_id': '11', 'favorite': true},
    ]);
  });

  testWidgets('blank dropdowns sort parents and categories alphabetically', (
    tester,
  ) async {
    final draft = blank();
    (draft['edit_options'] as Map)['categories'] = [
      {'id': '5', 'label': 'Snacks'},
      {'id': '4', 'label': 'Zucchini cakes', 'parent_label': 'Desserts'},
      {'id': '1', 'label': 'Desserts'},
      {'id': '3', 'label': 'brownies', 'parent_label': 'Desserts'},
      {'id': '2', 'label': 'Apple pies', 'parent_label': 'Desserts'},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: draft,
          householdId: '2',
          save: (_, body) async => {'recipe': body},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dropdowns = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .toList();
    expect(dropdowns[0].items!.map((item) => item.value).toList(), [
      '',
      'Desserts',
      'Snacks',
    ]);
    expect(dropdowns[1].items!.map((item) => item.value).toList(), [
      '2',
      '3',
      '1',
      '4',
      '__new',
    ]);
  });

  testWidgets(
    'blank entry fits a narrow phone and retains input after save failure',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final draft = blank()..remove('id');
      draft['title'] = '';
      draft['category_assignments'] = [];
      Map<String, dynamic>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeEditor(
            recipe: draft,
            householdId: '2',
            save: (_, body) async {
              submitted = Map.from(body);
              throw ApiException(502, 'Choose a category yourself or retry.');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect(submitted, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Recipe name'),
        'Birthday cake',
      );
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect(submitted?['category_assignments'], isEmpty);
      expect(find.text('Choose a category yourself or retry.'), findsOneWidget);
      expect(find.text('Birthday cake'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
      expect(find.text('Add picture'), findsOneWidget);
      expect(find.text('Blank recipe'), findsOneWidget);
      for (final label in [
        'Ingredients',
        'Method',
        'Source',
        'No ingredients recorded.',
        'No cooking steps recorded.',
        'Start cooking',
      ]) {
        expect(find.text(label), findsNothing);
      }
      for (final name in ['Text', 'Website', 'File', 'Camera']) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.text('Website'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RecipeImport>(find.byType(RecipeImport)).initialKind,
        'website',
      );
      expect(
        find.widgetWithText(TextField, 'Recipe website link'),
        findsOneWidget,
      );
      expect(find.text('Blank recipe'), findsNothing);
    },
  );
}
