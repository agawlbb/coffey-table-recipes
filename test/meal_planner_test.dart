import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/meal_planner.dart';
import 'package:coffey_table_recipes/src/meal_plan_ingredients.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> trashMeal(WidgetTester tester, String title) async {
  final tile = find.text(title);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(tester.getCenter(tile));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(
    tester.getCenter(find.byKey(const ValueKey('meal-trash'))),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pumpAndSettle();
}

class PlanFixture {
  int revision = 1;
  bool conflict = false;
  final writes = <Map<String, dynamic>>[];
  final reads = <String>[];
  final entries = <Map<String, dynamic>>[
    {
      'id': 'past',
      'recipe_id': '1',
      'kind': 'recipe',
      'title': 'Yesterday soup',
      'available': true,
      'plan_date': '2026-10-21',
    },
    {
      'id': 'today',
      'recipe_id': '1',
      'kind': 'recipe',
      'title': 'Today soup',
      'available': true,
      'plan_date': '2026-10-22',
    },
    {
      'id': 'idea',
      'recipe_id': '2',
      'kind': 'recipe',
      'title': 'Bread idea',
      'available': true,
      'plan_date': null,
    },
  ];
  Future<Map<String, dynamic>> request(String path) async {
    reads.add(path);
    if (path.contains('/pairings/')) {
      return {
        'recipes': [
          {'id': '3', 'title': 'Garlic bread'},
        ],
      };
    }
    if (path.endsWith('/recipes/5')) {
      return {
        'recipe': {'id': '5', 'title': 'Picker pasta', 'variation_family': []},
      };
    }
    if (path.contains('/recipes?')) {
      return {
        'recipes': [
          {'id': '5', 'title': 'Picker pasta'},
        ],
      };
    }
    return {
      'revision': revision,
      'today': '2026-10-22',
      'entries': entries.map((e) => Map<String, dynamic>.from(e)).toList(),
    };
  }

  Future<Map<String, dynamic>> save(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (conflict) {
      conflict = false;
      revision++;
      throw ApiException(
        409,
        'The meal plan changed. Review the updated plan and try again.',
      );
    }
    expect(body['revision'], revision);
    writes.add(Map.from(body));
    revision++;
    if (body['operation'] == 'remove') {
      entries.removeWhere((e) => e['id'] == body['id']);
    }
    if (body['operation'] == 'move') {
      entries.firstWhere((e) => e['id'] == body['id'])['plan_date'] =
          body['date'];
    }
    if (body['operation'] == 'add') {
      entries.add({
        'id': body['id'],
        'recipe_id': body['recipe_id'],
        'kind': body['kind'],
        'title': body['kind'] == 'leftovers' ? 'Leftovers' : 'Added recipe',
        'plan_date': body['date'],
        'available': true,
      });
    }
    return {'revision': revision, 'today': '2026-10-22'};
  }

  Widget app() => MaterialApp(
    home: Scaffold(
      body: MealPlanner(
        householdId: '1',
        householdName: 'Table',
        request: request,
        save: save,
        active: false,
        now: () => DateTime(2026, 10, 22),
      ),
    ),
  );
}

void main() {
  testWidgets('picker confirms variation selection and cancel adds nothing', (
    tester,
  ) async {
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeBrowser(
            householdId: '1',
            householdName: 'Table',
            mealPlanDestination: 'Friday, October 23',
            onSelect: (recipe) => selected = recipe,
            request: (path) async => path.endsWith('/recipes/5')
                ? {
                    'recipe': {
                      'id': '5',
                      'title': 'Pasta',
                      'variation_family': [
                        {'id': '5', 'title': 'Pasta', 'in_household': true},
                        {
                          'id': '6',
                          'title': 'Spicy pasta',
                          'in_household': true,
                        },
                        {
                          'id': '7',
                          'title': 'Removed pasta',
                          'in_household': false,
                        },
                      ],
                    },
                  }
                : {
                    'recipes': [
                      {'id': '5', 'title': 'Pasta'},
                    ],
                  },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pasta'));
    await tester.pumpAndSettle();
    expect(find.text('Removed pasta'), findsNothing);
    await tester.tap(find.text('Spicy pasta'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Pasta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spicy pasta'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(selected?['id'], '6');
  });

  testWidgets(
    'today is unshaded and scheduled meals cannot drop into unscheduled',
    (tester) async {
      final fixture = PlanFixture();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      final today = tester.widget<Container>(
        find.byKey(const ValueKey('meal-day-2026-10-22')),
      );
      expect((today.decoration as BoxDecoration).color, Colors.transparent);
      expect((today.decoration as BoxDecoration).border, isNotNull);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Today soup')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('meal-day-unscheduled'))),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('browser adds an unscheduled meal and provides View plan', (
    tester,
  ) async {
    final fixture = PlanFixture();
    var viewed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeBrowser(
            householdId: '1',
            householdName: 'Table',
            request: fixture.request,
            save: fixture.save,
            onViewMealPlan: () => viewed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Picker pasta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to meal plan'));
    await tester.pumpAndSettle();
    expect(fixture.writes.single['date'], isNull);
    expect(fixture.writes.single['recipe_id'], '5');
    expect(fixture.reads.where((p) => p.contains('/pairings/')), isEmpty);
    await tester.tap(find.text('View plan'));
    expect(viewed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 1100.0]) {
    testWidgets(
      'planner fits width $width with existing recipe browser on desktop',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = PlanFixture();
        await tester.pumpWidget(fixture.app());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byType(RecipeBrowser),
          width >= 950 ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'combines explicit compatible amounts without merging ambiguous units',
    () {
      final result = mealPlanIngredients([
        {
          'ingredient_name': 'Flour',
          'original_unit': 'cups',
          'quantity_decimal': '1',
        },
        {
          'ingredient_name': 'Flour',
          'original_unit': 'cup',
          'quantity_numerator': '1',
          'quantity_denominator': '2',
        },
        {
          'ingredient_name': 'Flour',
          'original_unit': 'g',
          'quantity_decimal': '100',
        },
        {'ingredient_name': 'Salt', 'quantity_text': 'to taste'},
        {'ingredient_name': 'Salt', 'quantity_text': 'a pinch'},
        {
          'ingredient_name': 'Onion',
          'quantity_decimal': '1',
          'is_optional': true,
        },
        {
          'ingredient_name': 'Onion',
          'quantity_decimal': '1',
          'is_optional': false,
        },
      ]);
      expect(result.length, 6);
      expect(result[0].name, 'Flour');
      expect(result[0].details, '1.5 cup');
      expect(result[1].details, '100 g');
      expect(result[2].details, 'to taste');
      expect(result[3].details, 'a pinch');
    },
  );

  testWidgets(
    'past meal removal cancels without a write, then confirms history change',
    (tester) async {
      final fixture = PlanFixture();
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await trashMeal(tester, 'Yesterday soup');
      expect(find.text('Change this past meal?'), findsOneWidget);
      expect(
        find.text('This will update your cooking history.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      await trashMeal(tester, 'Yesterday soup');
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(fixture.writes.single['confirm_past'], isTrue);
      expect(fixture.entries.where((e) => e['id'] == 'past'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('today supports placeholder tiles without history confirmation', (
    tester,
  ) async {
    final fixture = PlanFixture();
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final day = find.byKey(const ValueKey('meal-day-2026-10-22'));
    await tester.tap(find.descendant(of: day, matching: find.text('+ Add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leftovers'));
    await tester.pumpAndSettle();
    expect(fixture.writes.single['date'], '2026-10-22');
    expect(fixture.writes.single['kind'], 'leftovers');
    expect(fixture.writes.single['confirm_past'], isFalse);
    expect(find.text('Change this past meal?'), findsNothing);
    expect(fixture.reads.where((p) => p.contains('/pairings/')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'moving a dated meal does not offer pairings, moving an idea does',
    (tester) async {
      final fixture = PlanFixture();
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      Future<void> drop(String label, String date) async {
        final tile = find.text(label);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(tester.getCenter(tile));
        await tester.pump(const Duration(milliseconds: 600));
        final target = find.byKey(ValueKey('meal-day-$date'));
        await gesture.moveTo(tester.getTopLeft(target) + const Offset(60, 30));
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await drop('Today soup', '2026-10-23');
      expect(fixture.writes.last['operation'], 'move');
      expect(fixture.writes.last['date'], '2026-10-23');
      expect(fixture.reads.where((p) => p.contains('/pairings/')), isEmpty);
      await drop('Bread idea', '2026-10-22');
      expect(find.text('Frequently made together'), findsOneWidget);
      await tester.tap(find.text('Garlic bread'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add selected'));
      await tester.pumpAndSettle();
      expect(fixture.reads.where((p) => p.contains('/pairings/')).length, 1);
      expect(fixture.writes.last['recipe_id'], '3');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('stale plan is refreshed and does not silently retry a write', (
    tester,
  ) async {
    final fixture = PlanFixture()..conflict = true;
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await trashMeal(tester, 'Today soup');
    expect(fixture.writes, isEmpty);
    expect(
      find.text(
        'The meal plan changed. Review the updated plan and try again.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'recipe picker retains existing browser and adds directly to selected date',
    (tester) async {
      final fixture = PlanFixture();
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      final day = find.byKey(const ValueKey('meal-day-2026-10-22'));
      await tester.tap(find.descendant(of: day, matching: find.text('+ Add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recipe'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBrowser), findsOneWidget);
      await tester.tap(find.text('Picker pasta'));
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      expect(find.text('Add to Thursday, October 22, 2026'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(fixture.writes.single['recipe_id'], '5');
      expect(fixture.writes.single['date'], '2026-10-22');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
