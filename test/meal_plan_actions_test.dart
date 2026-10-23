import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/meal_plan_actions.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';

void main() {
  for (final variations in [false, true]) {
    testWidgets('recipe detail confirms addition with variations=$variations', (
      tester,
    ) async {
      final writes = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [mealPlanNotices],
          home: RecipeDetail(
            householdId: '1',
            recipeId: '5',
            title: 'Pasta',
            request: (path) async => path.contains('/meal-plan')
                ? {'revision': 1}
                : {
                    'recipe': {
                      'id': '5',
                      'title': 'Pasta',
                      'steps': [],
                      'ingredients': [],
                      'variation_family': variations
                          ? [
                              {
                                'id': '6',
                                'title': 'Spicy pasta',
                                'in_household': true,
                              },
                            ]
                          : [],
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
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.text('Add to meal plan'));
      await tester.pumpAndSettle();
      if (variations) {
        await tester.tap(find.text('Spicy pasta'));
      } else {
        expect(find.text('Add to meal plan?'), findsOneWidget);
      }
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(writes.single['recipe_id'], variations ? '6' : '5');
      expect(writes.single['date'], isNull);
      mealPlanNotices.dismiss();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final action in ['timeout', 'push', 'pop', 'section', 'late']) {
    testWidgets('addition notice clears on $action', (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      late BuildContext origin;
      final navigator = GlobalKey<NavigatorState>();
      Widget screen() => Scaffold(
        body: Builder(
          builder: (context) {
            origin = context;
            return TextButton(
              onPressed: () => addUnscheduledMeal(
                context,
                householdId: '1',
                recipe: {'id': '5', 'title': 'Pasta'},
                request: (_) async => {'revision': 1},
                save: (_, _) async => action == 'late' ? pending.future : {},
                viewPlan: () {},
              ),
              child: const Text('Plan'),
            );
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: child!,
          ),
          navigatorKey: navigator,
          navigatorObservers: [mealPlanNotices],
          home: Scaffold(
            body: TextButton(
              onPressed: () => navigator.currentState!.push(
                MaterialPageRoute<void>(builder: (_) => screen()),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      if (action != 'late') {
        expect(find.text('Added to meal plan'), findsOneWidget);
      }
      switch (action) {
        case 'timeout':
          await tester.pump(const Duration(seconds: 4));
          expect(find.text('Added to meal plan'), findsOneWidget);
          await tester.pump(const Duration(seconds: 1));
        case 'push':
          Navigator.of(origin).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Elsewhere')),
            ),
          );
        case 'pop':
          navigator.currentState!.pop();
        case 'section':
          mealPlanNotices.dismiss();
        case 'late':
          Navigator.of(origin).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Elsewhere')),
            ),
          );
          pending.complete({});
      }
      await tester.pumpAndSettle();
      expect(find.text('Added to meal plan'), findsNothing);
      expect(find.text('View plan'), findsNothing);
      mealPlanNotices.dismiss();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
