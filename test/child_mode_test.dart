import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/child_mode.dart';
import 'package:coffey_table_recipes/src/meal_planner.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:coffey_table_recipes/src/blank_recipe_detail.dart';
import 'package:coffey_table_recipes/src/recipe_variation.dart';
import 'package:coffey_table_recipes/src/recipe_import.dart';
import 'package:coffey_table_recipes/src/recipe_shopping_selector.dart';
import 'package:coffey_table_recipes/src/meal_plan_ingredients.dart';
import 'package:coffey_table_recipes/src/administration.dart';
import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'meal_planner_test.dart' show PlanFixture;

void main() {
  test(
    'offline writes stop before durable queue and API allows favorites',
    () async {
      var writes = 0;
      final local = LocalData(
        key: 'child-fixture',
        fetch: (_) async => {},
        send: (_, body) async {
          writes++;
          return {};
        },
        readStore: (_) async => null,
        writeStore: (_, value) async {
          writes++;
        },
      );
      childMode.value = true;
      expect(() => local.save('/households/1/recipes', {}), throwsStateError);
      expect(writes, 0);
      final api = RecipeApi(
        baseUrl: 'https://example.com',
        client: MockClient((request) async {
          writes++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.request('/households/1/shopping-list', 'fixture', body: {}),
        throwsStateError,
      );
      expect(writes, 0);
      await api.request(
        '/households/1/recipes/2/favorites',
        'fixture',
        body: {'favorite': true},
      );
      expect(writes, 1);
      local.dispose();
      api.close();
    },
  );
  testWidgets('policy changes rebuild an open protected view', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChildModeScope(
          child: Builder(
            builder: (context) =>
                Text(childModeOf(context) ? 'Locked' : 'Open'),
          ),
        ),
      ),
    );
    expect(find.text('Open'), findsOneWidget);
    childMode.value = true;
    await tester.pump();
    expect(find.text('Locked'), findsOneWidget);
  });
  tearDown(() => childMode.value = false);
  test('child AI requests are rejected before network access', () async {
    childMode.value = true;
    var calls = 0;
    final api = RecipeApi(
      baseUrl: 'https://example.com',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    for (final path in [
      '/households/1/recipe-import',
      '/households/1/recipe-photo',
      '/households/1/category-image',
      '/households/1/recipes/2/variation',
      '/admin/parent-categories/1/category-image',
    ]) {
      await expectLater(
        api.request(path, 'child-fixture', body: {}),
        throwsStateError,
      );
    }
    expect(calls, 0);
    api.close();
  });
  testWidgets('child cannot use AI import or variation screens directly', (
    tester,
  ) async {
    var calls = 0;
    Future<Map<String, dynamic>> request(
      String path,
      Map<String, dynamic> body,
    ) async {
      calls++;
      return {};
    }

    for (final screen in <Widget>[
      RecipeImport(householdId: '1', request: request),
      RecipeVariation(
        householdId: '1',
        parentRecipeId: '2',
        parentTitle: 'Soup',
        request: request,
      ),
    ]) {
      childMode.value = false;
      await tester.pumpWidget(MaterialApp(home: ChildModeScope(child: screen)));
      await tester.pumpAndSettle();
      childMode.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Unavailable in child mode.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    expect(calls, 0);
  });
  testWidgets(
    'child recipe browsing never requests generated category images',
    (tester) async {
      childMode.value = true;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '1',
            householdName: 'Home',
            request: (_) async => {
              'view': 'categories',
              'category_nodes': [
                {'id': '5', 'label': 'Breakfast', 'needs_ai_image': true},
              ],
            },
            save: (_, body) async {
              calls++;
              return {};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Breakfast'), findsOneWidget);
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('policy permits favorites and PIN changes only', () {
    childMode.value = true;
    for (final path in [
      '/households/1/meal-plan',
      '/households/1/shopping-list',
      '/households/1/recipes',
      '/admin/users/2/delete',
      '/households/1/recipe-import',
      '/households/1/recipe-photo',
      '/households/1/category-image',
      '/households/1/recipes/2/variation',
    ]) {
      expect(() => requireChildModeWrite(path), throwsStateError);
    }
    requireChildModeWrite('/households/1/recipes/2/favorites');
    requireChildModeWrite('/me/child-mode');
  });
  testWidgets('child can view planner without dragging or adding', (
    tester,
  ) async {
    childMode.value = true;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = PlanFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealPlanner(
            householdId: '1',
            householdName: 'Home',
            request: fixture.request,
            save: fixture.save,
            active: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Today soup'), findsOneWidget);
    expect(find.byType(RecipeBrowser), findsNothing);
    expect(find.byType(LongPressDraggable<Map<String, dynamic>>), findsNothing);
    final buttons = tester.widgetList<TextButton>(
      find.widgetWithText(TextButton, '+ Add'),
    );
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('recipe keeps favorite but hides child-restricted actions', (
    tester,
  ) async {
    childMode.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '1',
          recipeId: '5',
          title: 'Soup',
          request: (_) async => {
            'recipe': {
              'id': '5',
              'title': 'Soup',
              'in_household': true,
              'steps': [
                {'instruction': 'Stir'},
              ],
              'ingredients': [],
              'photos': [],
            },
          },
          save: (_, body) async => {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Start cooking',
      'Add to meal plan',
      'Request variation',
      'Add to shopping list',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(find.byTooltip('Edit recipe'), findsNothing);
    expect(find.byTooltip('Delete recipe'), findsNothing);
    expect(find.byTooltip('Favorite (hold for household)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('child shopping list hides add input while retaining items', (
    tester,
  ) async {
    childMode.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '1',
          householdName: 'Home',
          request: (path, {body}) async => {
            'revision': 0,
            'items': [
              {
                'id': '1',
                'name': 'Milk',
                'department': 'Dairy',
                'checked': false,
              },
            ],
            'departments': ['Dairy'],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Add item'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('blank child recipe hides editing and AI import controls', (
    tester,
  ) async {
    childMode.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlankRecipeDetail(
            title: 'Blank',
            photos: const [],
            favorite: false,
            onPicture: () {},
            onMealPlan: () {},
            onAttach: () {},
            onImport: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Blank'), findsOneWidget);
    for (final label in [
      'Add picture',
      'Add to meal plan',
      'Add to my household',
      'Import recipe',
    ]) {
      expect(find.text(label), findsNothing);
    }
  });
  testWidgets('enabling requires matching PINs before saving', (tester) async {
    final writes = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => changeChildMode(context, (body) async {
                writes.add(body);
                return {'enabled': true};
              }),
              child: const Text('Mode'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mode'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.enterText(find.byType(TextField).last, '5678');
    await tester.tap(find.text('Enable'));
    await tester.pump();
    expect(writes, isEmpty);
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(writes.single, {'enabled': true, 'pin': '1234'});
    expect(childMode.value, isTrue);
  });
  testWidgets('blank warning updates when meal dates change', (tester) async {
    var blanks = ['Mystery casserole'];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeShoppingSelector(
          ingredients: const [],
          onAdd: (_) async {},
          blankRecipeTitles: () => blanks,
          onChooseDates: (_) async {
            blanks = [];
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mystery casserole'), findsOneWidget);
    expect(
      find.textContaining('Ingredients they require are not shown'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Choose meal dates'));
    await tester.pumpAndSettle();
    expect(find.text('Mystery casserole'), findsNothing);
    expect(
      find.textContaining('Ingredients they require are not shown'),
      findsNothing,
    );
  });
  test(
    'blank recipe warning deduplicates occurrences over date batches',
    () async {
      List<String>? titles;
      await loadMealPlanIngredients(
        (path) async => path.contains('/ingredients')
            ? {
                'ingredients': [],
                'blank_recipes': [
                  {'id': '1', 'title': 'Mystery casserole'},
                  {'id': '1', 'title': 'Mystery casserole'},
                ],
              }
            : {
                'entries': [
                  {'kind': 'recipe', 'plan_date': '2026-10-23'},
                  {'kind': 'recipe', 'plan_date': '2028-10-23'},
                ],
              },
        '/households/1/meal-plan',
        DateTime(2026, 10, 23),
        DateTime(2028, 10, 23),
        onBlankRecipes: (rows) => titles = rows,
      );
      expect(titles, ['Mystery casserole']);
    },
  );
  testWidgets('administrator selects registered user and confirms reset', (
    tester,
  ) async {
    final writes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AdministrationPage(
          request: (path, {body}) async {
            if (body != null) {
              writes.add(path);
              expect(body['confirm'], isTrue);
              return {'reset_pending': true};
            }
            if (path == '/me') {
              return {
                'user': {'id': '1', 'account_role': 'administrator'},
              };
            }
            return {
              'users': [
                {
                  'id': '2',
                  'display_name': 'Alex',
                  'email': 'alex@example.com',
                },
              ],
              'people': [],
              'households': [],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable child mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex').first);
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(writes, ['/admin/users/2/reset-child-mode']);
  });
}
