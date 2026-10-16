import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:coffey_table_recipes/src/recipe_variation.dart';
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

Future<void> openVariation(WidgetTester tester, RecipeSave request) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecipeVariation(
                  householdId: '2',
                  parentRecipeId: '10',
                  parentTitle: 'Original soup',
                  request: request,
                ),
              ),
            ),
            child: const Text('Open variation'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open variation'));
  await tester.pumpAndSettle();
}

Future<void> prepare(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'Make it dairy-free');
  await tester.ensureVisible(find.text('Prepare variation'));
  await tester.tap(find.text('Prepare variation'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => offlineStatus.value = false);
  tearDown(() => offlineStatus.value = false);

  testWidgets('AI-approved parent cover previews and saves as a new photo', (
    tester,
  ) async {
    const image =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNoaGgAAAMEAYFL09IQAAAAAElFTkSuQmCC';
    Map<String, dynamic>? saved;
    final response = variationDraft();
    response['parent_cover_review'] = {
      'appropriate': true,
      'reason': 'The finished dish looks the same.',
    };
    (response['recipe'] as Map)['photos'] = [
      {
        'id': 'new-parent-cover',
        'image_base64': image,
        'caption': 'Original cover',
        'attribution': 'Original photographer',
        'is_cover': 1,
      },
    ];
    await openVariation(tester, (path, body) async {
      if (path.endsWith('/variation')) return response;
      saved = body;
      return {
        'recipe': {...body, 'id': '11'},
      };
    });
    await prepare(tester);
    final editor = tester.widget<RecipeEditor>(find.byType(RecipeEditor));
    expect((editor.recipe['photos'] as List).single['image_base64'], image);
    expect(find.byType(Image), findsWidgets);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    final photo = (saved!['photos'] as List).single as Map;
    expect(photo['id'], startsWith('new-'));
    expect(photo['image_base64'], image);
    expect(photo['attribution'], 'Original photographer');
    expect(saved!.containsKey('parent_cover_review'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clarifies cumulatively and saves a new recipe only on approval',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await openVariation(tester, (path, body) async {
        calls.add({'path': path, 'body': jsonDecode(jsonEncode(body))});
        if (path.endsWith('/recipes')) {
          return {
            'recipe': {...body, 'id': '11'},
          };
        }
        if (calls.length == 1) {
          return variationDraft(['Which milk alternative?']);
        }
        if (calls.length == 2) return variationDraft(['Keep the butter?']);
        return variationDraft();
      });
      await prepare(tester);
      expect(find.text('Which milk alternative?'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Oat milk');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Use olive oil');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Review recipe'), findsOneWidget);
      expect(find.byType(RecipeEditor), findsOneWidget);
      expect(find.text('How the recipe changed'), findsOneWidget);
      expect(
        find.text(
          'Replaced cream with oat milk and reduced simmering to keep the soup smooth.',
        ),
        findsOneWidget,
      );
      expect(find.text('Variation'), findsWidgets);
      expect(calls.length, 3);
      final first = calls.first['body'] as Map;
      expect(first['request_id'], matches(RegExp(r'^[a-f0-9]{32}$')));
      for (final call in calls) {
        expect(call['path'], '/households/2/recipes/10/variation');
        expect((call['body'] as Map)['request_id'], first['request_id']);
      }
      expect((calls[2]['body'] as Map)['answers'], [
        {'question': 'Which milk alternative?', 'answer': 'Oat milk'},
        {'question': 'Keep the butter?', 'answer': 'Use olive oil'},
      ]);
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect(calls.last['path'], '/households/2/recipes');
      expect((calls.last['body'] as Map)['parent_recipe_id'], '10');
      expect((calls.last['body'] as Map)['import_key'], 'stable-variation-key');
      expect((calls.last['body'] as Map)['source_type'], 'ai_variation');
      expect((calls.last['body'] as Map).containsKey('id'), isFalse);
      expect(
        (calls.last['body'] as Map).containsKey('change_description'),
        isFalse,
      );
      expect(
        jsonEncode(calls.last['body']),
        isNot(contains('Replaced cream with oat milk')),
      );
      expect(find.text('Open variation'), findsOneWidget);
    },
  );

  testWidgets('generation failure retains input and retry identity', (
    tester,
  ) async {
    final bodies = <Map<String, dynamic>>[];
    await openVariation(tester, (_, body) async {
      bodies.add(body);
      if (bodies.length == 1) {
        throw ApiException(503, 'Please try again later.');
      }
      return variationDraft(['Which milk alternative?']);
    });
    await prepare(tester);
    expect(find.text('Please try again later.'), findsOneWidget);
    expect(find.text('Make it dairy-free'), findsOneWidget);
    await tester.tap(find.text('Prepare variation'));
    await tester.pumpAndSettle();
    expect(bodies.length, 2);
    expect(bodies[1]['request_id'], bodies[0]['request_id']);
    expect(bodies[1]['changes'], bodies[0]['changes']);
  });

  testWidgets('edited failed request starts a fresh generation identity', (
    tester,
  ) async {
    final bodies = <Map<String, dynamic>>[];
    await openVariation(tester, (_, body) async {
      bodies.add(body);
      throw ApiException(503, 'Please try again later.');
    });
    await prepare(tester);
    await tester.enterText(find.byType(TextField).first, 'Make it gluten-free');
    await tester.ensureVisible(find.text('Prepare variation'));
    await tester.tap(find.text('Prepare variation'));
    await tester.pumpAndSettle();
    expect(bodies[1]['request_id'], isNot(bodies[0]['request_id']));
    expect(bodies[1]['changes'], 'Make it gluten-free');
  });

  testWidgets('late success while confirming cancel can still be reviewed', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    await openVariation(tester, (_, _) => response.future);
    await tester.enterText(find.byType(TextField).first, 'Make it dairy-free');
    await tester.ensureVisible(find.text('Prepare variation'));
    await tester.tap(find.text('Prepare variation'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    response.complete(variationDraft());
    await tester.pumpAndSettle();
    expect(find.text('Discard recipe variation?'), findsOneWidget);
    expect(find.text('Review recipe'), findsNothing);
    await tester.tap(find.text('Keep working'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review variation'));
    await tester.tap(find.text('Review variation'));
    await tester.pumpAndSettle();
    expect(find.text('Review recipe'), findsOneWidget);
  });

  testWidgets(
    'draft cannot update the parent even if response contains its id',
    (tester) async {
      final response = variationDraft();
      (response['recipe'] as Map)['id'] = '10';
      var saved = false;
      await openVariation(tester, (path, body) async {
        if (path.endsWith('/variation')) return response;
        expect(path, '/households/2/recipes');
        expect(body.containsKey('id'), isFalse);
        expect(body['parent_recipe_id'], '10');
        saved = true;
        return {
          'recipe': {...body, 'id': '11'},
        };
      });
      await prepare(tester);
      expect((response['recipe'] as Map)['id'], '10');
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
    },
  );

  testWidgets(
    'follow-up failure retains answers without duplicating them on retry',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      await openVariation(tester, (_, body) async {
        bodies.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
        if (bodies.length == 1) {
          return variationDraft(['Which milk alternative?']);
        }
        if (bodies.length == 2) throw ApiException(503, 'Retry the question.');
        return variationDraft();
      });
      await prepare(tester);
      await tester.enterText(find.byType(TextField).first, 'Oat milk');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Oat milk'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect((bodies.last['answers'] as List).length, 1);
      expect(bodies[2]['answers'], bodies[1]['answers']);
      expect(find.text('Review recipe'), findsOneWidget);
    },
  );

  testWidgets('empty request and unanswered question never reach the server', (
    tester,
  ) async {
    var calls = 0;
    await openVariation(tester, (_, _) async {
      calls++;
      return variationDraft(['Which milk alternative?']);
    });
    await tester.ensureVisible(find.text('Prepare variation'));
    await tester.tap(find.text('Prepare variation'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      find.text('Describe what you would like to change.'),
      findsOneWidget,
    );
    await prepare(tester);
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      find.text('Answer each question, or enter “unknown”.'),
      findsOneWidget,
    );
  });

  for (final back in [false, true]) {
    testWidgets(
      'review ${back ? 'Back' : 'Cancel'} returns to origin without saving',
      (tester) async {
        var calls = 0;
        await openVariation(tester, (_, _) async {
          calls++;
          return variationDraft();
        });
        await prepare(tester);
        expect(find.text('Review recipe'), findsOneWidget);
        if (back) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text('Cancel'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Open variation'), findsOneWidget);
        expect(find.byType(RecipeVariation), findsNothing);
        expect(calls, 1);
      },
    );
  }

  testWidgets('edited approval can keep working or discard without saving', (
    tester,
  ) async {
    var calls = 0;
    await openVariation(tester, (_, _) async {
      calls++;
      return variationDraft();
    });
    await prepare(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Recipe name'),
      'Changed variation',
    );
    await tester.tap(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Recipe name'), findsOneWidget);
    expect(find.text('Changed variation'), findsNWidgets(2));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Open variation'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets(
    'cancel during generation ignores a late response and repeated taps',
    (tester) async {
      final response = Completer<Map<String, dynamic>>();
      var calls = 0;
      await openVariation(tester, (_, _) {
        calls++;
        return response.future;
      });
      await tester.enterText(
        find.byType(TextField).first,
        'Make it dairy-free',
      );
      await tester.ensureVisible(find.text('Prepare variation'));
      await tester.tap(find.text('Prepare variation'));
      await tester.tap(find.text('Prepare variation'));
      await tester.pump();
      expect(calls, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      response.complete(variationDraft());
      await tester.pumpAndSettle();
      expect(find.text('Open variation'), findsOneWidget);
      expect(find.text('Review recipe'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('save retry retains the draft and stable import identity', (
    tester,
  ) async {
    final saves = <Map<String, dynamic>>[];
    await openVariation(tester, (path, body) async {
      if (path.endsWith('/variation')) return variationDraft();
      expect(path, '/households/2/recipes');
      saves.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
      if (saves.length == 1) throw ApiException(503, 'Save needs a retry.');
      return {
        'recipe': {...body, 'id': '11'},
      };
    });
    await prepare(tester);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Save needs a retry.'), findsWidgets);
    expect(find.text('Review recipe'), findsOneWidget);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(saves[1]['import_key'], saves[0]['import_key']);
    expect(find.text('Open variation'), findsOneWidget);
  });

  testWidgets('offline preparation is disabled and recovers when connected', (
    tester,
  ) async {
    var calls = 0;
    await openVariation(tester, (_, _) async {
      calls++;
      return variationDraft();
    });
    offlineStatus.value = true;
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Make it dairy-free');
    await tester.ensureVisible(find.text('Prepare variation'));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Prepare variation'),
    );
    expect(button.onPressed, isNull);
    expect(calls, 0);
    offlineStatus.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare variation'));
    await tester.pumpAndSettle();
    expect(calls, 1);
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
        final titleFinder = find.descendant(
          of: find.byType(ListView),
          matching: find.text('Dairy-free soup'),
        );
        final title = tester.getRect(titleFinder);
        expect(title.width, closeTo(352, 0.1));
        expect(
          tester.getBottomLeft(titleFinder).dy,
          lessThan(tester.getTopLeft(find.byType(PopupMenuButton<String>)).dy),
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
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
