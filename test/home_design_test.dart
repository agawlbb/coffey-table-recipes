import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestUser implements User {
  @override
  String get uid => 'test-user';
  @override
  String? get displayName => 'Alex Example';
  @override
  String? get email => 'alex@example.test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [320.0, 1000.0]) {
    testWidgets('recipes are the home and settings preserve search at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paths = <String>[];
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
      }) async {
        paths.add(path);
        if (path == '/me') {
          return {
            'households': [
              {'id': '2', 'name': 'Coffey', 'role': 'owner'},
              {'id': '3', 'name': 'Other household', 'role': 'member'},
            ],
          };
        }
        if (path.endsWith('/people')) {
          return {
            'people': [
              {'display_name': 'Alex', 'user_id': 'test-user'},
            ],
          };
        }
        return {
          'recipes': [
            {'id': '9', 'title': 'Family soup'},
          ],
          'next_offset': null,
        };
      }

      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(user: TestUser(), request: request),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Family soup'), findsOneWidget);
      expect(find.text('People at your table'), findsNothing);
      expect(find.text('Your household'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
      expect(paths.where((p) => p.endsWith('/people')), isEmpty);
      await tester.enterText(find.byType(TextField), 'soup');
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Household & people'));
      await tester.pumpAndSettle();
      expect(find.text('Your household'), findsOneWidget);
      expect(find.text('Family soup'), findsNothing);
      await tester.tap(find.text('People at your table'));
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Add person'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recipes').last);
      await tester.pumpAndSettle();
      expect(find.text('Family soup'), findsOneWidget);
      expect(find.text('soup'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Household & people'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coffey'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other household').last);
      await tester.pumpAndSettle();
      expect(find.text('Add person'), findsNothing);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recipes').last);
      await tester.pumpAndSettle();
      expect(
        paths.any((path) => path.startsWith('/households/3/recipes?')),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
