import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';

Map<String, dynamic> recipe() => {
  'id': '9',
  'revision': '1',
  'title': 'Soup',
  'original_language': 'en',
  'measurement_system': 'us',
  'ingredients': [
    {
      'id': '11',
      'ingredient_name': 'Milk',
      'original_text': '1 cup milk',
      'scale_quantity': true,
    },
  ],
  'steps': [
    {'id': '21', 'instruction': 'Simmer'},
    {'id': '22', 'instruction': 'Rest'},
  ],
  'actions': [
    {
      'id': '31',
      'step_id': '21',
      'action_type': 'timer',
      'label': 'Simmer timer',
      'duration_seconds': 60,
    },
    {
      'id': '32',
      'step_id': '21',
      'action_type': 'rest',
      'label': 'Second timer',
      'duration_seconds': 120,
    },
  ],
  'photos': [],
  'groups': [],
  'tags': [],
  'pairings': [],
  'category_assignments': [],
};

Future<void> section(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('section shortcuts preserve edits and show useful row previews', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: recipe(),
          householdId: '2',
          save: (_, body) async {
            submitted = body;
            throw ApiException(500, 'Draft retained');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Go to ingredients'));
    await tester.pumpAndSettle();
    expect(find.text('1 cup milk'), findsOneWidget);
    await section(tester, '1. Milk');
    final line = find.widgetWithText(
      TextFormField,
      'Ingredient line (as displayed)',
    );
    await tester.ensureVisible(line);
    await tester.enterText(line, '2 cups milk');
    await tester.pump();
    expect(
      find.text('Unsaved changes · Save when you’re ready'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byTooltip('Go to steps & actions'));
    await tester.tap(find.byTooltip('Go to steps & actions'));
    await tester.pumpAndSettle();
    expect(find.text('Simmer'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(
      (submitted!['ingredients'] as List).single['original_text'],
      '2 cups milk',
    );
    expect(find.text('Draft retained'), findsOneWidget);
  });

  testWidgets('save reveals and scrolls to errors inside collapsed sections', (
    tester,
  ) async {
    var saved = false;
    final draft = recipe();
    (draft['steps'] as List).first['instruction'] = '';
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: draft,
          householdId: '2',
          save: (_, body) async {
            saved = true;
            return {'recipe': body};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.text('Enter Instructions'), findsOneWidget);
    final error = tester.getRect(find.text('Enter Instructions'));
    expect(error.top, greaterThan(0));
    expect(
      error.bottom,
      lessThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 40,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'server-confirmed edits replace persisted offline recipe details',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      String? disk;
      const path = '/households/2/recipes/9';
      final cache = OfflineRecipes(
        key: 'editor-test',
        read: (_) async => disk,
        write: (_, value) async {
          disk = value;
        },
        fetch: (_) async => {'recipe': recipe()},
      );
      await cache.request(path);
      await cache.rememberSavedRecipe(path, {
        'recipe': {...recipe(), 'title': 'Updated soup', 'revision': '2'},
      });
      cache.close();
      final restored = OfflineRecipes(
        key: 'editor-test',
        read: (_) async => disk,
        write: (_, value) async {},
        fetch: (_) async => throw StateError('Must use the saved response'),
      );
      offlineStatus.value = true;
      try {
        expect(
          (await restored.request(path))['recipe']['title'],
          'Updated soup',
        );
      } finally {
        restored.close();
        offlineStatus.value = false;
      }
    },
  );
  testWidgets('pencil opens editor and save updates the displayed recipe', (
    tester,
  ) async {
    final original = recipe();
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '2',
          recipeId: '9',
          title: 'Soup',
          request: (_) async => {'recipe': original},
          save: (path, body) async {
            submitted = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
            return {
              'recipe': {...body, 'title': 'New soup', 'revision': '2'},
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit recipe'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, 'Recipe name');
    await tester.enterText(name, 'New soup');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(submitted?['title'], 'New soup');
    expect(original['title'], 'Soup');
    expect(find.text('Recipe saved'), findsOneWidget);
    expect(find.text('New soup'), findsNWidgets(2));
  });
  testWidgets('discard protects text edits and save failure retains draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecipeEditor(
                  recipe: recipe(),
                  householdId: '2',
                  save: (_, _) async =>
                      throw ApiException(409, 'Recipe changed.'),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Recipe name'),
      'Unsaved',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Recipe changed.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Unsaved'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Edit recipe'), findsNothing);
  });
  testWidgets(
    'reordering actions and steps preserves associations and removing a step removes actions',
    (tester) async {
      Map<String, dynamic>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeEditor(
            recipe: recipe(),
            householdId: '2',
            save: (_, body) async {
              submitted = body;
              throw ApiException(500, 'Test saved draft');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await section(tester, 'Steps & actions');
      await section(tester, 'Step 1');
      await section(tester, 'Second timer');
      final action = find
          .ancestor(
            of: find.text('Second timer'),
            matching: find.byType(ExpansionTile),
          )
          .first;
      final up = find.descendant(
        of: action,
        matching: find.byTooltip('Move up'),
      );
      await tester.ensureVisible(up);
      await tester.tap(up);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((submitted!['actions'] as List).first['id'], '32');
      expect((submitted!['actions'] as List).first['step_id'], '21');
      final step = find
          .ancestor(
            of: find.text('Step 1'),
            matching: find.byType(ExpansionTile),
          )
          .first;
      final remove = find
          .descendant(of: step, matching: find.byTooltip('Remove'))
          .last;
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(submitted!['actions'], isEmpty);
      expect((submitted!['steps'] as List).single['id'], '22');
    },
  );
  testWidgets('upload and camera add photos to the draft with a single cover', (
    tester,
  ) async {
    final sources = <ImageSource>[];
    Map<String, dynamic>? submitted;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT1sAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: recipe(),
          householdId: '2',
          pickImage: (source) async {
            sources.add(source);
            return XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: 'plate.png',
            );
          },
          save: (_, body) async {
            submitted = body;
            throw ApiException(500, 'Test saved draft');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Photos');
    for (final label in ['Upload image', 'Use camera']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(sources, [ImageSource.gallery, ImageSource.camera]);
    final photos = submitted!['photos'] as List;
    expect(photos.length, 2);
    expect(photos.first['is_cover'], 1);
    expect(photos.last['is_cover'], 0);
    expect(photos.first['image_base64'], isNotEmpty);
  });
  testWidgets('editor remains usable on a narrow phone screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: recipe(),
          householdId: '2',
          save: (_, body) async => {'recipe': body},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await section(tester, 'Steps & actions');
    await section(tester, 'Step 1');
    expect(tester.takeException(), isNull);
  });
}
