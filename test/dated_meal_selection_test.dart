import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/meal_plan_actions.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';

import 'meal_planner_test.dart' show PlanFixture;

void main() {
  testWidgets('blank recipe viewer requires a date before adding', (
    tester,
  ) async {
    final writes = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [mealPlanNotices],
        home: RecipeDetail(
          householdId: '1',
          recipeId: '5',
          title: 'Blank dish',
          request: (path) async => path.contains('/meal-plan')
              ? {'revision': 1, 'today': '2026-10-22'}
              : {
                  'recipe': {
                    'id': '5',
                    'title': 'Blank dish',
                    'source_type': 'blank',
                    'variation_family': [],
                    'photos': [],
                  },
                },
          save: (_, body) async {
            writes.add(body);
            return {};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to meal plan'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('choose-meal-2026-10-24')));
    await tester.pumpAndSettle();
    expect(writes.single['date'], '2026-10-24');
    mealPlanNotices.dismiss();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'date selector lists seven household days and cancel writes nothing',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => selected = await selectMealDate(
                  context,
                  DateTime(2026, 10, 22),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      for (var day = 22; day <= 28; day++) {
        expect(
          find.byKey(ValueKey('choose-meal-2026-10-$day')),
          findsOneWidget,
        );
      }
      expect(find.text('Thursday, October 22, 2026'), findsOneWidget);
      expect(find.text('Another date…'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('choose-meal-2026-10-23')));
      await tester.pumpAndSettle();
      expect(selected, '2026-10-23');
    },
  );
  testWidgets('calendar fallback allows a past meal only after confirmation', (
    tester,
  ) async {
    final writes = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [mealPlanNotices],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => addDatedMeal(
                context,
                householdId: '1',
                recipe: {'id': '5', 'title': 'Pasta', 'variation_family': []},
                request: (_) async => {'revision': 1, 'today': '2026-10-22'},
                save: (_, body) async {
                  writes.add(body);
                  return {};
                },
              ),
              child: const Text('Plan'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Another date…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Another date…'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('21').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Change this past meal?'), findsOneWidget);
    expect(writes, isEmpty);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(writes.single['date'], '2026-10-21');
    expect(writes.single['confirm_past'], isTrue);
    mealPlanNotices.dismiss();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('wide planner recipe tap selects date and offers pairings once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = PlanFixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(find.text('Unscheduled'), findsNothing);
    await tester.tap(find.text('Picker pasta'));
    await tester.pumpAndSettle();
    expect(fixture.writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('choose-meal-2026-10-23')));
    await tester.pumpAndSettle();
    expect(fixture.writes.single['date'], '2026-10-23');
    expect(find.text('Frequently made together'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
