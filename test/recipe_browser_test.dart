import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(Uri.parse(paths.last).queryParameters['q'], '');
    await tester.tap(find.byKey(const ValueKey('recipe-breadcrumb-1')));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters['scope'], '5');
    await tester.tap(find.text('Muffins'));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byTooltip('Back one level')).dy,
      lessThan(tester.getTopLeft(find.text('Bran muffins')).dy),
    );
    await tester.tap(find.byTooltip('Back one level'));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters['scope'], '5');
    expect(Uri.parse(paths.last).queryParameters['q'], '');
    expect(find.text('Muffins'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recipe-breadcrumb-0')));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters.containsKey('scope'), isFalse);
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
    expect(paths.last, '/households/2/recipes?q=farine&offset=0&tree=1');
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
