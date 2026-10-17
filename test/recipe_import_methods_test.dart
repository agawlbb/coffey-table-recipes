import 'package:coffey_table_recipes/src/recipe_import.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> methodDraft(String label, String key) => {
  'title': 'Lentil soup - $label',
  '_import_method_label': label,
  'import_key': List.filled(64, key).join(),
  'original_language': 'en',
  'measurement_system': 'us',
  'source_type': 'Website',
  'source_url': 'https://example.test/soup',
  'ingredients': [
    {'id': 'i', 'ingredient_name': 'lentils', 'original_text': '1 cup lentils'},
  ],
  'steps': [
    {
      'id': 's',
      'instruction': label == 'Stovetop'
          ? 'Simmer for 25 minutes.'
          : 'Pressure cook for 15 minutes.',
    },
  ],
  'category_assignments': [],
  'actions': [],
  'photos': [],
};
Map<String, dynamic> methodChoice() => {
  'recipe': {
    ...methodDraft('choose', 'a'),
    '_import_method_choice_required': true,
  },
  'questions': ['Stovetop, Instant Pot, or both?'],
  'requires_method_choice': true,
  'method_choices': [
    {'id': 'stovetop', 'label': 'Stovetop'},
    {'id': 'instant-pot', 'label': 'Instant Pot'},
  ],
};

Future<void> prepare(
  WidgetTester tester,
  RecipeSave request, {
  void Function(Map<String, dynamic>?)? completed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder: (_) => RecipeImport(
                    householdId: '2',
                    initialKind: 'website',
                    request: request,
                  ),
                ),
              );
              completed?.call(result);
            },
            child: const Text('Open import'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open import'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextField).first,
    'https://example.test/soup',
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Prepare recipe'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Prepare recipe'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Update recipe'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Update recipe'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('child clarification preserves the saved parent link', (
    tester,
  ) async {
    Map<String, dynamic>? childSave;
    await prepare(tester, (path, body) async {
      if (path.endsWith('/recipe-import')) {
        if (body['kind'] == 'website') return methodChoice();
        if (body['method_selection'] == 'both') {
          return {
            'recipe': methodDraft('Stovetop', 'b'),
            'questions': [],
            'related_imports': [
              {
                'recipe': methodDraft('Instant Pot', 'c'),
                'questions': ['Which pressure release method?'],
              },
            ],
          };
        }
        final reply = methodDraft('Instant Pot', 'c');
        reply.remove('_import_method_label');
        return {'recipe': reply, 'questions': []};
      }
      if (body['parent_recipe_id'] != null) childSave = body;
      return {
        'recipe': {...body, 'id': '10', 'revision': '1'},
      };
    });
    await choose(tester, 'Both, as linked variations');
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Which pressure release method?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Natural release');
    await tester.ensureVisible(find.text('Update recipe'));
    await tester.tap(find.text('Update recipe'));
    await tester.pumpAndSettle();
    final editor = tester.widget<RecipeEditor>(find.byType(RecipeEditor));
    expect(editor.recipe['parent_recipe_id'], '10');
    expect(editor.recipe['_import_method_label'], 'Instant Pot');
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(childSave!['parent_recipe_id'], '10');
  });
  testWidgets('required method selection cannot bypass to mixed review', (
    tester,
  ) async {
    await prepare(tester, (_, body) async => methodChoice());
    expect(find.text('Stovetop'), findsOneWidget);
    expect(find.text('Instant Pot'), findsOneWidget);
    expect(find.text('Review with missing details'), findsNothing);
    expect(find.byType(RecipeEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'single method is requested and reviewed without saving the other',
    (tester) async {
      Map<String, dynamic>? sent;
      await prepare(tester, (_, body) async {
        if (body['kind'] == 'website') return methodChoice();
        sent = body;
        return {'recipe': methodDraft('Instant Pot', 'b'), 'questions': []};
      });
      await choose(tester, 'Instant Pot');
      expect(sent!['method_selection'], 'instant-pot');
      expect(sent!['supports_related_imports'], true);
      final editor = tester.widget<RecipeEditor>(find.byType(RecipeEditor));
      expect(editor.recipe['title'], 'Lentil soup - Instant Pot');
      expect(editor.recipe['parent_recipe_id'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
  for (final cancelChild in [false, true]) {
    testWidgets(
      'both reviews link to saved parent and preserve it on cancel: $cancelChild',
      (tester) async {
        final saves = <Map<String, dynamic>>[];
        Map<String, dynamic>? completed;
        await prepare(tester, (path, body) async {
          if (path.endsWith('/recipe-import')) {
            if (body['kind'] == 'website') return methodChoice();
            return {
              'recipe': methodDraft('Stovetop', 'b'),
              'questions': [],
              'related_imports': [
                {'recipe': methodDraft('Instant Pot', 'c'), 'questions': []},
              ],
            };
          }
          saves.add(Map<String, dynamic>.from(body));
          return {
            'recipe': {
              ...body,
              'id': saves.length == 1 ? '10' : '11',
              'revision': '1',
            },
          };
        }, completed: (value) => completed = value);
        await choose(tester, 'Both, as linked variations');
        expect(saves, isEmpty);
        expect(find.textContaining('Recipe 1 of 2'), findsOneWidget);
        await tester.tap(find.text('Save recipe'));
        await tester.pumpAndSettle();
        expect(saves.length, 1);
        expect(saves.first['parent_recipe_id'], isNull);
        final child = tester.widget<RecipeEditor>(find.byType(RecipeEditor));
        expect(child.recipe['parent_recipe_id'], '10');
        expect(child.variationParentTitle, 'Lentil soup - Stovetop');
        expect(child.allowEditSource, false);
        expect(find.textContaining('Recipe 2 of 2'), findsOneWidget);
        if (cancelChild) {
          await tester.tap(find.text('Cancel'));
        } else {
          await tester.tap(find.text('Save recipe'));
        }
        await tester.pumpAndSettle();
        expect(completed!['id'], '10');
        expect(saves.length, cancelChild ? 1 : 2);
        if (!cancelChild) {
          expect(saves.last['parent_recipe_id'], '10');
          expect(saves.last['import_key'], isNot(saves.first['import_key']));
        }
        expect(find.text('Open import'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'failed parent save retains both drafts and never starts child save',
    (tester) async {
      var attempts = 0;
      await prepare(tester, (path, body) async {
        if (path.endsWith('/recipe-import')) {
          return body['kind'] == 'website'
              ? methodChoice()
              : {
                  'recipe': methodDraft('Stovetop', 'b'),
                  'questions': [],
                  'related_imports': [
                    {
                      'recipe': methodDraft('Instant Pot', 'c'),
                      'questions': [],
                    },
                  ],
                };
        }
        attempts++;
        throw ApiException(503, 'Save failed; retry.');
      });
      await choose(tester, 'Both, as linked variations');
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text('Save failed; retry.'), findsOneWidget);
      expect(find.textContaining('Recipe 1 of 2'), findsOneWidget);
    },
  );
}
