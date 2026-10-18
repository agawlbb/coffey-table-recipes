import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/shopping_departments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_design_test.dart' show TestUser;

void main() {
  testWidgets(
    'shopping view retains menu and reloads shared department settings',
    (tester) async {
      var revision = 0;
      var departments = ['Produce', 'Dairy & eggs'];
      var items = <Map<String, dynamic>>[
        {
          'id': 'a',
          'name': 'Apples',
          'checked': false,
          'department': 'Produce',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(
            user: TestUser(),
            request: (path, {body}) async {
              if (path == '/me') {
                return {
                  'user': {'id': '42'},
                  'households': [
                    {'id': '2', 'name': 'Coffey', 'role': 'member'},
                  ],
                };
              }
              if (path.endsWith('/people')) return {'people': []};
              if (path.endsWith('/shopping-list')) {
                if (body != null) {
                  expect(body['revision'], revision);
                  revision++;
                  departments = (body['departments'] as List).cast<String>();
                  items = (body['items'] as List).cast<Map<String, dynamic>>();
                }
                return {
                  'revision': revision,
                  'departments': departments,
                  'items': items,
                };
              }
              return {'recipes': [], 'next_offset': null};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('Household & people'), findsNothing);
      expect(find.text('Shopping list departments'), findsNothing);
      await tester.tap(find.text('Shopping list'));
      await tester.pumpAndSettle();
      expect(find.text('Apples'), findsOneWidget);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      await tester.tap(find.byTooltip('User menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Household & people'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping list departments'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rename Produce'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Farm stand');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(items.single['department'], 'Farm stand');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Shopping list departments'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('Household & people').hitTestable(), findsNothing);
      expect(
        find.text('Shopping list departments').hitTestable(),
        findsNothing,
      );
      await tester.tap(find.text('Shopping list'));
      await tester.pumpAndSettle();
      expect(find.text('Farm stand'), findsOneWidget);
      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('Produce'), findsNothing);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recipes'));
      await tester.pumpAndSettle();
      expect(find.text('Apples'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'department configuration adds, validates, reorders and safely removes',
    (tester) async {
      var revision = 0;
      var departments = ['Produce', 'Dairy'];
      var items = <Map<String, dynamic>>[
        {
          'id': 'a',
          'name': 'Apples',
          'checked': false,
          'department': 'Produce',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ShoppingDepartmentsScreen(
            householdId: '2',
            request: (path, {body}) async {
              if (body != null) {
                expect(body['revision'], revision++);
                departments = (body['departments'] as List).cast<String>();
                items = (body['items'] as List).cast<Map<String, dynamic>>();
              }
              return {
                'revision': revision,
                'departments': departments,
                'items': items,
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add department'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'produce');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Department already exists'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Pet supplies');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(departments, ['Produce', 'Dairy', 'Pet supplies']);
      final handle = find.byIcon(Icons.drag_handle).last;
      final target = tester.getCenter(find.byIcon(Icons.drag_handle).first);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(target - const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveBy(const Offset(0, -5));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(departments, ['Produce', 'Pet supplies', 'Dairy']);
      await tester.tap(find.byTooltip('Remove Produce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(items.single['department'], 'Produce');
      await tester.tap(find.byTooltip('Remove Produce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(departments, isNot(contains('Produce')));
      expect(items.single['name'], 'Apples');
      expect(items.single['department'], '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('conflicting department edits reload current household state', (
    tester,
  ) async {
    var conflict = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingDepartmentsScreen(
          householdId: '2',
          request: (path, {body}) async {
            if (body != null) {
              conflict = true;
              throw ApiException(409, 'The shopping list changed.');
            }
            return {
              'revision': conflict ? 2 : 1,
              'departments': conflict ? ['Deli'] : ['Produce'],
              'items': [],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Produce'));
    await tester.pumpAndSettle();
    expect(find.text('Deli'), findsOneWidget);
    expect(find.text('Produce'), findsNothing);
    expect(find.text('The shopping list changed.'), findsOneWidget);
  });
}
