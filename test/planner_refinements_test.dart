import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:coffey_table_recipes/src/meal_planner.dart';
import 'package:coffey_table_recipes/src/restaurant_manager.dart';

import 'home_design_test.dart' show TestUser;
import 'meal_planner_test.dart' show PlanFixture;

class SectionUser extends TestUser {
  @override
  String get uid => 'section-test';
}

void main() {
  for (final section in ['recipes', 'shopping', 'planner']) {
    testWidgets('device restores $section then remembers recipe root', (
      tester,
    ) async {
      final saved = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(
            user: SectionUser(),
            readPreference: (_) async => section,
            writePreference: (_, value) async {
              saved.add(value);
            },
            request: (path, {body}) async {
              if (path == '/me') {
                return {
                  'user': {'id': '1'},
                  'households': [
                    {'id': '1', 'name': 'Home', 'role': 'owner'},
                  ],
                };
              }
              if (path.contains('/meal-plan')) {
                return {'revision': 1, 'today': '2026-10-23', 'entries': []};
              }
              if (path.endsWith('/shopping-list')) {
                return {'revision': 1, 'items': []};
              }
              return {'recipes': [], 'people': []};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find
            .text(
              section == 'shopping'
                  ? 'Shopping list'
                  : section == 'planner'
                  ? 'Meal planner'
                  : 'Recipes',
            )
            .first,
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recipes').last);
      await tester.pumpAndSettle();
      expect(saved.last, 'recipes');
      expect(find.text('All Recipes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('restaurant selector ends with generic Restaurant', (
    tester,
  ) async {
    final fixture = PlanFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealPlanner(
            householdId: '1',
            householdName: 'Home',
            request: (path) async => path.endsWith('/restaurants')
                ? {
                    'revision': 0,
                    'items': [
                      {'id': 'cafe', 'name': 'Cafe'},
                    ],
                  }
                : fixture.request(path),
            save: fixture.save,
            active: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final day = find.byKey(const ValueKey('meal-day-2026-10-22'));
    await tester.tap(find.descendant(of: day, matching: find.text('+ Add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurant outing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Cafe'), findsWidgets);
    expect(find.text('Restaurant'), findsWidgets);
    await tester.tap(find.text('Cafe').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(fixture.writes.single['restaurant_id'], 'cafe');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('restaurant manager adds and renames preserving reserved logo', (
    tester,
  ) async {
    final writes = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RestaurantManager(
          householdId: '1',
          request: (_) async => {'revision': 0, 'items': []},
          save: (_, body) async {
            writes.add(body);
            return {'revision': writes.length};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add restaurant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cafe');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes.single['items'][0]['logo_reference'], isNull);
    await tester.tap(find.byTooltip('Edit restaurant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New Cafe');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes.last['items'][0]['id'], writes.first['items'][0]['id']);
    await tester.pumpWidget(const SizedBox());
  });
}
