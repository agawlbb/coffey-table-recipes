import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/meal_plan_ingredients.dart';
import 'package:coffey_table_recipes/src/meal_planner.dart';
import 'package:coffey_table_recipes/src/recipe_shopping_selector.dart';
import 'package:coffey_table_recipes/src/shopping_ingredient.dart';

import 'meal_planner_test.dart' show PlanFixture;

void main() {
  test('customary amounts round upward to standard cooking measures', () {
    for (final pair in [
      ('1.0833333', '1 1/8 cup'),
      ('0.2', '1/4 cup'),
      ('0.26', '1/3 cup'),
      ('0.4', '1/2 cup'),
      ('0.6', '5/8 cup'),
      ('0.64', '2/3 cup'),
      ('0.8', '7/8 cup'),
      ('1.9', '2 cup'),
      ('1.3333333', '1 1/3 cup'),
      ('0', '0 cup'),
      ('0.001', '1/8 cup'),
    ]) {
      expect(
        mealPlanIngredients([
          {
            'ingredient_name': 'Cocoa',
            'original_unit': 'cup',
            'quantity_decimal': pair.$1,
          },
        ]).single.details,
        pair.$2,
      );
    }
    expect(
      mealPlanIngredients([
        {
          'ingredient_name': 'Cocoa',
          'original_unit': 'g',
          'quantity_decimal': '1.0833333',
        },
      ]).single.details,
      '1.0833333 g',
    );
    expect(
      mealPlanIngredients([
        {
          'ingredient_name': 'Cocoa',
          'original_unit': 'cup',
          'quantity_decimal': '0.54',
        },
        {
          'ingredient_name': 'Cocoa',
          'original_unit': 'cup',
          'quantity_decimal': '0.54',
        },
      ]).single.details,
      '1 1/8 cup',
    );
  });

  test(
    'quantities use customary fractions and trim decimals including totals',
    () {
      final items = mealPlanIngredients([
        {
          'ingredient_name': 'Flour',
          'original_unit': 'cups',
          'quantity_decimal': '1.250000',
        },
        {
          'ingredient_name': 'Flour',
          'original_unit': 'cup',
          'quantity_decimal': '.250000',
        },
        {
          'ingredient_name': 'Butter',
          'original_unit': 'tbsp',
          'quantity_decimal': '.333333',
        },
        {
          'ingredient_name': 'Water',
          'original_unit': 'ml',
          'quantity_decimal': '125.500000',
        },
        {
          'ingredient_name': 'Salt',
          'original_unit': 'g',
          'quantity_decimal': '2.000000',
        },
        {
          'ingredient_name': 'Oil',
          'original_unit': 'cup',
          'quantity_decimal': '.5',
          'quantity_max_decimal': '1.000000',
        },
        {'ingredient_name': 'Pepper', 'quantity_text': 'to taste'},
      ]);
      expect(items.map((i) => i.details), [
        '1 1/2 cup',
        '1/3 tbsp',
        '125.5 ml',
        '2 g',
        '1/2–1 cup',
        'to taste',
      ]);
    },
  );
  test(
    'all future planned dates fetched in bounded nonoverlapping ranges',
    () async {
      final paths = <String>[];
      final result = await loadMealPlanIngredients(
        (path) async {
          paths.add(path);
          if (!path.contains('/ingredients?')) {
            return {
              'entries': [
                for (final date in [
                  '2026-10-22',
                  '2027-10-23',
                  '2029-04-01',
                  '2026-10-21',
                  null,
                ])
                  {'kind': 'recipe', 'plan_date': date},
                {'kind': 'leftovers', 'plan_date': '2030-01-01'},
              ],
            };
          }
          return {
            'ingredients': [
              {
                'ingredient_name': 'Flour',
                'original_unit': 'cup',
                'quantity_decimal': '.5',
              },
            ],
          };
        },
        '/meal-plan',
        DateTime(2026, 10, 22),
        DateTime(2199, 12, 31),
      );
      expect(paths.first, '/meal-plan?from=2026-10-22&to=2199-12-31');
      expect(paths.skip(1), [
        '/meal-plan/ingredients?from=2026-10-22&to=2027-10-23',
        '/meal-plan/ingredients?from=2029-04-01&to=2029-04-01',
      ]);
      expect(result.single.details, '1 cup');
    },
  );
  testWidgets(
    'planner opens all-future ingredients directly; calendar cancel keeps list',
    (tester) async {
      final fixture = PlanFixture();
      final paths = <String>[];
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealPlanner(
              householdId: '1',
              householdName: 'Table',
              active: false,
              save: fixture.save,
              request: (path) async {
                paths.add(path);
                if (path.contains('/ingredients?')) {
                  return {
                    'ingredients': [
                      {
                        'ingredient_name': 'Flour',
                        'original_unit': 'cup',
                        'quantity_decimal': '1.5000',
                      },
                    ],
                  };
                }
                if (path.endsWith('/shopping-list')) return {'items': []};
                return fixture.request(path);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Refresh meal plan'), findsNothing);
      await tester.tap(find.text('Ingredients'));
      await tester.pumpAndSettle();
      expect(paths.any((p) => p.endsWith('to=2199-12-31')), isTrue);
      expect(find.text('Flour'), findsOneWidget);
      expect(find.text('1 1/2 cup'), findsOneWidget);
      expect(find.byType(DateRangePickerDialog), findsNothing);
      await tester.tap(find.byTooltip('Choose meal dates'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Flour'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'custom dates replace rows and clear prior ingredient selections',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeShoppingSelector(
            ingredients: const [ShoppingIngredient('Flour')],
            onAdd: (_) async {},
            onChooseDates: (_) async =>
                ++calls == 1 ? null : const [ShoppingIngredient('Milk')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flour'));
      await tester.tap(find.byTooltip('Choose meal dates'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.byTooltip('Choose meal dates'));
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Flour'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    },
  );
}
