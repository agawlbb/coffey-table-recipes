import 'dart:async';

import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_value.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'refresh keeps recipes visible while new category supplement stalls',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var supplement = false;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '2',
            householdName: 'Table',
            cachedRequest: (path) async =>
                Uri.parse(path).queryParameters['tree'] == '1'
                ? {
                    'view': 'categories',
                    'category_nodes': [
                      {'id': '5', 'label': 'Breakfast'},
                    ],
                  }
                : supplement
                ? null
                : {
                    'recipes': [
                      {'id': '9', 'title': 'Saved muffins'},
                    ],
                  },
            request: (path) async {
              if (Uri.parse(path).queryParameters['tree'] == '1') {
                return {
                  'view': 'categories',
                  'category_nodes': [
                    {'id': '5', 'label': 'Breakfast'},
                  ],
                };
              }
              supplement = true;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh recipes'));
      await tester.pump();
      expect(supplement, isTrue);
      expect(find.text('Saved muffins'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // A second refresh must retain text even if only category metadata is cached.
      await tester.tap(find.byTooltip('Refresh recipes'));
      await tester.pump();
      expect(find.text('Saved muffins'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.complete({
        'recipes': [
          {'id': '10', 'title': 'New muffins'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('New muffins'), findsOneWidget);
      expect(find.text('Saved muffins'), findsNothing);
    },
  );

  testWidgets('stalled local cache cannot prevent an online recipe read', (
    tester,
  ) async {
    final cached = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Table',
          cachedRequest: (_) => cached.future,
          request: (_) async => {
            'recipes': [
              {'id': '9', 'title': 'Online muffins'},
            ],
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Online muffins'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    cached.complete(null);
    await tester.pumpAndSettle();
  });
  testWidgets(
    'returning from shopping and reconnecting show partial cached recipes immediately',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var shopping = false, browserVersion = 0, calls = 0;
      late StateSetter update;
      offlineStatus.value = false;
      addTearDown(() => offlineStatus.value = false);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return IndexedStack(
                index: shopping ? 1 : 0,
                children: [
                  RecipeBrowser(
                    key: ValueKey(browserVersion),
                    householdId: '2',
                    householdName: 'Table',
                    cachedRequest: (_) async => {
                      '_cache_needs_refresh': true,
                      'recipes': [
                        {'id': '9', 'title': 'Saved muffins'},
                      ],
                    },
                    request: (_) {
                      calls++;
                      return pending.future;
                    },
                  ),
                  const Text('Shopping list'),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Saved muffins'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      update(() => shopping = true);
      await tester.pump();
      update(() {
        shopping = false;
        browserVersion++;
      });
      await tester.pump();
      await tester
          .pump(); // Paint the cached result after the recreated page loads it.
      expect(find.text('Saved muffins'), findsOneWidget);
      offlineStatus.value = true;
      offlineStatus.value = false;
      await tester.pump();
      expect(find.text('Saved muffins'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(calls, greaterThanOrEqualTo(3));
      pending.complete({
        'recipes': [
          {'id': '10', 'title': 'Fresh muffins'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Fresh muffins'), findsOneWidget);
      expect(find.text('Saved muffins'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cached categories stay usable while supplementary recipe request stalls',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '2',
            householdName: 'Table',
            cachedRequest: (path) async =>
                Uri.parse(path).queryParameters['tree'] == '1'
                ? {
                    'view': 'categories',
                    'category_nodes': [
                      {'id': '5', 'label': 'Breakfast'},
                    ],
                  }
                : null,
            request: (_) => pending.future,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('Breakfast'));
      await tester.pump();
      expect(find.byTooltip('Back one level'), findsOneWidget);
      pending.complete({'recipes': []});
      await tester.pumpAndSettle();
    },
  );

  testWidgets('stalled uncached read stops loading and offers retry', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Table',
          request: (_) => pending.future,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    pending.complete({'recipes': []});
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('refresh access denial removes previously cached content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Table',
          cachedRequest: (_) async => {
            'recipes': [
              {'id': '9', 'title': 'Saved muffins'},
            ],
          },
          request: (_) async => throw ApiException(403, 'Access denied'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved muffins'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh recipes'));
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('Saved muffins'), findsNothing);
  });
  testWidgets('All Recipes cancels slow category navigation', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Table',
          request: (path) async {
            if (Uri.parse(path).queryParameters.containsKey('scope')) {
              return pending.future;
            }
            return {
              'category_nodes': [
                {'id': '5', 'label': 'Breakfast', 'recipe_count': 1},
              ],
              'recipes': [
                {'id': '9', 'title': 'Root recipe'},
              ],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Breakfast'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('recipe-breadcrumb-0')));
    await tester.pumpAndSettle();
    expect(find.text('Root recipe'), findsOneWidget);
    pending.complete({
      'recipes': [
        {'id': '10', 'title': 'Late category recipe'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('Late category recipe'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('phone search keeps layout valid while keyboard is open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Table',
          request: (_) async => {'recipes': <Map<String, dynamic>>[]},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'chicken');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'cached category navigation avoids slow requests and refresh fetches',
    (tester) async {
      var calls = 0;
      final pending = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '2',
            householdName: 'Coffey',
            cachedRequest: (path) async {
              final q = Uri.parse(path).queryParameters;
              return q['scope'] == null
                  ? {
                      'category_nodes': [
                        {'id': '5', 'label': 'Breakfast', 'recipe_count': 1},
                      ],
                      'recipes': <Map<String, dynamic>>[],
                    }
                  : {
                      'recipes': [
                        {'id': '9', 'title': 'Cached muffins'},
                      ],
                    };
            },
            request: (_) {
              calls++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Breakfast'));
      await tester.pumpAndSettle();
      expect(find.text('Cached muffins'), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.byTooltip('Back one level'));
      await tester.pumpAndSettle();
      expect(find.text('Breakfast'), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.byTooltip('Refresh recipes'));
      await tester.pump();
      expect(calls, 1);
      pending.complete({
        'recipes': [
          {'id': '10', 'title': 'Fresh recipe'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Fresh recipe'), findsOneWidget);
    },
  );

  testWidgets('slow category artwork never blocks text or navigation', (
    tester,
  ) async {
    final image = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Coffey',
          request: (_) async => {
            'category_nodes': [
              {
                'id': '5',
                'label': 'Breakfast',
                'recipe_count': 1,
                'needs_ai_image': true,
              },
            ],
            'recipes': [
              {'id': '9', 'title': 'Muffins'},
            ],
          },
          save: (_, body) => image.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Muffins'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Breakfast'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back one level'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    image.complete({'image_url': 'https://example.test/category.jpg'});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps main category order and alphabetizes nested browsing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Coffey',
          request: (path) async {
            final query = Uri.parse(path).queryParameters;
            if (query['tree'] == '1') {
              final nested = query.containsKey('scope');
              return {
                'view': 'categories',
                'category_nodes': [
                  {
                    'id': '1',
                    'label': nested ? 'Zucchini' : 'Main dishes',
                    'recipe_count': 2,
                  },
                  {
                    'id': '2',
                    'label': nested ? 'apple sides' : 'Side dishes',
                    'recipe_count': 2,
                  },
                  if (!nested)
                    {'id': '3', 'label': 'Breakfast', 'recipe_count': 2},
                ],
              };
            }
            return {
              'recipes': [
                if (query['offset'] == '0') ...[
                  {'id': '9', 'title': 'Zesty soup'},
                  {'id': '10', 'title': 'apple pie'},
                ] else
                  {'id': '11', 'title': 'Banana bread'},
              ],
              'next_offset': query['offset'] == '0' ? 2 : null,
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    double y(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(y('Main dishes'), lessThan(y('Side dishes')));
    expect(y('Side dishes'), lessThan(y('Breakfast')));
    expect(y('apple pie'), lessThan(y('Zesty soup')));
    await tester.tap(find.text('Main dishes'));
    await tester.pumpAndSettle();
    expect(y('apple sides'), lessThan(y('Zucchini')));
    await tester.tap(find.text('Load more recipes'));
    await tester.pumpAndSettle();
    expect(y('apple pie'), lessThan(y('Banana bread')));
    expect(y('Banana bread'), lessThan(y('Zesty soup')));
  });

  testWidgets('returning to iOS shows recipes saved by the share extension', (
    tester,
  ) async {
    var sharedRecipeSaved = false;
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Coffey',
          request: (path) async {
            paths.add(path);
            return {
              'recipes': [
                {'id': '9', 'title': 'Original recipe'},
                if (sharedRecipeSaved)
                  {'id': '10', 'title': 'Recipe saved from share sheet'},
              ],
              'next_offset': null,
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recipe saved from share sheet'), findsNothing);
    await tester.enterText(find.byType(TextField), 'recipe');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    sharedRecipeSaved = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Recipe saved from share sheet'), findsOneWidget);
    expect(Uri.parse(paths.last).queryParameters['q'], 'recipe');
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('categories precede scoped recipes and survive pagination', (
    tester,
  ) async {
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Coffey',
          request: (path) async {
            paths.add(path);
            final query = Uri.parse(path).queryParameters;
            if (query['tree'] == '1') {
              return {
                'view': 'categories',
                'category_nodes': [
                  {
                    'id': '5',
                    'label': 'Breakfast',
                    'image_key': 'breakfast',
                    'recipe_count': 2,
                  },
                ],
                'recipes': [],
              };
            }
            return {
              'recipes': [
                {
                  'id': query['offset'] == '0' ? '9' : '10',
                  'title': query['offset'] == '0' ? 'Bran muffins' : 'Pancakes',
                },
              ],
              'next_offset': query['offset'] == '0' ? 1 : null,
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Bran muffins'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Breakfast')).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('scope-recipes-divider')))
            .dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('scope-recipes-divider'))).dy,
      lessThan(tester.getTopLeft(find.text('Bran muffins')).dy),
    );
    final categoryCard = tester.widget<Card>(
      find.ancestor(of: find.text('Breakfast'), matching: find.byType(Card)),
    );
    final recipeCard = tester.widget<Card>(
      find.ancestor(of: find.text('Bran muffins'), matching: find.byType(Card)),
    );
    expect(categoryCard.color, isNot(recipeCard.color));
    await tester.tap(find.text('Load more recipes'));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters['tree'], '0');
    expect(Uri.parse(paths.last).queryParameters['offset'], '1');
    expect(find.text('Breakfast'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pancakes'),
      150,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Pancakes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('three-level browsing scopes search and back navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Coffey',
          request: (path) async {
            paths.add(path);
            final query = Uri.parse(path).queryParameters;
            if ((query['q'] ?? '').isNotEmpty || query['scope'] == '8') {
              return {
                'view': 'recipes',
                'recipes': [
                  {'id': '9', 'title': 'Bran muffins'},
                ],
                'next_offset': null,
              };
            }
            return {
              'view': 'categories',
              'recipes': [],
              'category_nodes': [
                if (query['scope'] == null)
                  {
                    'id': '5',
                    'label': 'Breakfast',
                    'image_key': 'breakfast',
                    'recipe_count': 1,
                  }
                else
                  {
                    'id': '8',
                    'label': 'Muffins',
                    'image_key': 'muffins',
                    'recipe_count': 1,
                  },
              ],
              'next_offset': null,
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Breakfast'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bran');
    await tester.tap(find.byTooltip('Search recipes'));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters.containsKey('scope'), isFalse);
    expect(find.text('Bran muffins'), findsOneWidget);
    await tester.tap(find.byTooltip('Back one level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Breakfast'));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters['scope'], '5');
    await tester.enterText(find.byType(TextField), 'bran');
    await tester.tap(find.byTooltip('Search recipes'));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters['scope'], '5');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muffins'));
    await tester.pumpAndSettle();
    expect(find.text('Bran muffins'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bran');
    await tester.tap(find.byTooltip('Search recipes'));
    await tester.pumpAndSettle();
    final query = Uri.parse(paths.last).queryParameters;
    expect(query['scope'], '8');
    expect(query['q'], 'bran');
    expect(query['offset'], '0');
    expect(find.text('All Recipes'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Muffins'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recipe-breadcrumb-2')));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters['scope'], '8');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tester.tap(find.byKey(const ValueKey('recipe-breadcrumb-1')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.labelText,
      'Search breakfast',
    );
    await tester.tap(find.text('Muffins'));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byTooltip('Back one level')).dy,
      lessThan(tester.getTopLeft(find.text('Bran muffins')).dy),
    );
    await tester.tap(find.byTooltip('Back one level'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.labelText,
      'Search breakfast',
    );
    expect(find.text('Muffins'), findsOneWidget);
    final requestsBeforeRoot = paths.length;
    await tester.tap(find.byKey(const ValueKey('recipe-breadcrumb-0')));
    await tester.pumpAndSettle();
    expect(paths.length, requestsBeforeRoot);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.labelText,
      'Search all recipes',
    );
    expect(find.text('Breakfast'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('browse searches the household and opens structured details', (
    tester,
  ) async {
    final paths = <String>[];
    Future<Map<String, dynamic>> request(String path) async {
      paths.add(path);
      if (path.contains('/recipes/9')) {
        return {
          'recipe': {
            'id': '9',
            'title': 'Crêpes',
            'original_language': 'fr',
            'servings': '4.0000',
            'revision': '1',
            'ingredients': [
              {'group_id': null, 'original_text': '250 g de farine'},
            ],
            'steps': [
              {'id': '4', 'position': 1, 'instruction': 'Préchauffer à 180°C.'},
            ],
            'actions': [
              {
                'step_id': '4',
                'temperature_value': '180.0000',
                'temperature_unit': 'C',
              },
            ],
            'source_title': 'Family recipe',
            'groups': [],
            'tags': [],
            'photos': [],
            'related': [],
            'pairings': [],
          },
        };
      }
      return {
        'recipes': [
          {'id': '9', 'title': 'Crêpes', 'servings': '4.0000'},
        ],
        'next_offset': null,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '2',
          householdName: 'Coffey',
          request: request,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Crêpes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'farine');
    await tester.tap(find.byTooltip('Search recipes'));
    await tester.pumpAndSettle();
    expect(
      paths.last,
      '/households/2/recipes?q=farine&offset=0&tree=0&families=1',
    );
    await tester.tap(find.text('Crêpes'));
    await tester.pumpAndSettle();
    expect(paths.last, '/households/2/recipes/9');
    expect(find.text('• 250 g de farine'), findsOneWidget);
    expect(find.text('1. Préchauffer à 180°C.'), findsOneWidget);
    expect(find.text('180°C'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.getCenter(find.byType(BackButton)).dy, lessThan(100));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('display removes decimal padding without changing quantities', () {
    expect(recipeValue('1.25000000'), '1.25');
    expect(recipeValue('180.0000'), '180');
    expect(recipeValue('0.00000001'), '0.00000001');
  });
}
