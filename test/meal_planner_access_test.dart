import 'dart:async';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/meal_planner.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'meal_planner_test.dart' show PlanFixture, trashMeal;

void main() {
  testWidgets(
    'late authorized read cannot restore meals after a newer access denial',
    (tester) async {
      final fixture = PlanFixture();
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealPlanner(
              householdId: '1',
              householdName: 'Table',
              active: false,
              now: () => DateTime(2026, 10, 22),
              save: fixture.save,
              request: (path) {
                calls++;
                if (calls == 2) return pending.future;
                if (calls == 3) {
                  return Future.error(
                    ApiException(
                      404,
                      'Household not found.',
                      code: 'household_not_found',
                    ),
                  );
                }
                return fixture.request(path);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh meal plan'));
      await tester.pump();
      await tester.tap(find.byTooltip('Refresh meal plan'));
      await tester.pumpAndSettle();
      pending.complete(await fixture.request('/snapshot'));
      await tester.pumpAndSettle();
      expect(find.text('Today soup'), findsNothing);
      expect(find.text('Ingredients'), findsNothing);
      expect(find.text('Household not found.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'write denial clears readiness without a speculative read restoring it',
    (tester) async {
      final fixture = PlanFixture();
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealPlanner(
              householdId: '1',
              householdName: 'Table',
              active: false,
              now: () => DateTime(2026, 10, 22),
              request: fixture.request,
              save: (path, body) async => throw ApiException(
                401,
                'Please sign in again.',
                code: 'invalid_token',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reads = fixture.reads.length;
      await trashMeal(tester, 'Today soup');
      expect(find.text('Today soup'), findsNothing);
      expect(find.text('Ingredients'), findsNothing);
      expect(find.text('Please sign in again.'), findsOneWidget);
      expect(fixture.reads.length, reads);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final failure in [
    ApiException(404, 'Household not found.', code: 'household_not_found'),
    ApiException(403, 'Account disabled.', code: 'account_disabled'),
    ApiException(401, 'Please sign in again.', code: 'invalid_token'),
    ApiException(401, 'Please sign in again.', code: 'account_deleted'),
  ]) {
    testWidgets(
      'clears meals and action readiness for ${failure.code}; retry restores fresh state',
      (tester) async {
        final fixture = PlanFixture();
        Object? error;
        Future<Map<String, dynamic>> request(String path) async {
          if (error != null) throw error;
          return fixture.request(path);
        }

        await tester.binding.setSurfaceSize(const Size(1100, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MealPlanner(
                householdId: '1',
                householdName: 'Table',
                request: request,
                save: fixture.save,
                now: () => DateTime(2026, 10, 22),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Today soup'), findsOneWidget);
        expect(find.text('Bread idea'), findsOneWidget);
        error = failure;
        await tester.tap(find.byTooltip('Refresh meal plan'));
        await tester.pumpAndSettle();
        expect(find.text('Today soup'), findsNothing);
        expect(find.text('Bread idea'), findsNothing);
        expect(find.text('Unscheduled'), findsNothing);
        expect(find.byType(RecipeBrowser), findsNothing);
        expect(find.text('+ Add'), findsNothing);
        expect(find.text('Ingredients'), findsNothing);
        expect(find.text(failure.message), findsOneWidget);
        // A temporary failure after access loss must not resurrect old entries.
        error = ApiException(503, 'Temporarily unavailable.');
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Today soup'), findsNothing);
        fixture.entries.clear();
        fixture.revision = 20;
        error = null;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Ingredients'), findsOneWidget);
        expect(find.text('Today soup'), findsNothing);
        final day = find.byKey(const ValueKey('meal-day-2026-10-22'));
        await tester.tap(
          find.descendant(of: day, matching: find.text('+ Add')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leftovers'));
        await tester.pumpAndSettle();
        expect(fixture.writes.single['revision'], 20);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final failure in [
    TimeoutException('offline'),
    ApiException(503, 'Service unavailable.'),
    ApiException(429, 'Try later.'),
    ApiException(404, 'Endpoint not found.', code: 'not_found'),
    ApiException(404, 'Recipe missing.', code: 'recipe_not_found'),
    ApiException(403, 'Upstream failure.'),
  ]) {
    testWidgets('retains useful cached plan for $failure', (tester) async {
      final fixture = PlanFixture();
      var failed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealPlanner(
              householdId: '1',
              householdName: 'Table',
              active: false,
              now: () => DateTime(2026, 10, 22),
              save: fixture.save,
              request: (path) async {
                if (failed) throw failure;
                return fixture.request(path);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      failed = true;
      await tester.tap(find.byTooltip('Refresh meal plan'));
      await tester.pumpAndSettle();
      expect(find.text('Today soup'), findsOneWidget);
      expect(find.text('Bread idea'), findsOneWidget);
      expect(find.text('Ingredients'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'poll loss while mounted and hidden clears cached entries on return',
    (tester) async {
      final fixture = PlanFixture();
      final pending = Completer<Map<String, dynamic>>();
      var poll = false;
      var active = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: IndexedStack(
                  index: active ? 0 : 1,
                  children: [
                    MealPlanner(
                      householdId: '1',
                      householdName: 'Table',
                      active: active,
                      now: () => DateTime(2026, 10, 22),
                      save: fixture.save,
                      request: (path) =>
                          poll ? pending.future : fixture.request(path),
                    ),
                    const Text('Other tab'),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      poll = true;
      await tester.pump(const Duration(seconds: 30));
      update(() => active = false);
      await tester.pump();
      pending.completeError(
        ApiException(404, 'Household not found.', code: 'household_not_found'),
      );
      await tester.pumpAndSettle();
      update(() => active = true);
      await tester.pumpAndSettle();
      expect(find.text('Today soup'), findsNothing);
      expect(find.text('+ Add'), findsNothing);
      expect(find.text('Household not found.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pending past confirmation cannot write after access loss and recovery',
    (tester) async {
      final fixture = PlanFixture();
      var denied = false;
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealPlanner(
              householdId: '1',
              householdName: 'Table',
              now: () => DateTime(2026, 10, 22),
              save: fixture.save,
              request: (path) async {
                if (denied) {
                  throw ApiException(
                    404,
                    'Household not found.',
                    code: 'household_not_found',
                  );
                }
                return fixture.request(path);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await trashMeal(tester, 'Yesterday soup');
      expect(find.text('Change this past meal?'), findsOneWidget);
      denied = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      denied = false;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
