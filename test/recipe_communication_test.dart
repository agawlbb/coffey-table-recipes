import 'dart:async';

import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_design_test.dart' show TestUser;

void main() {
  testWidgets(
    'startup paints cached recipes without waiting for account refresh',
    (tester) async {
      final network = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(
            user: TestUser(),
            request: (_, {body}) => network.future,
            cachedRequest: (path) async => path == '/me'
                ? {
                    'households': [
                      {'id': '1', 'name': 'Saved table'},
                    ],
                  }
                : {
                    'recipes': [
                      {'id': '9', 'title': 'Cached soup'},
                    ],
                  },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Cached soup'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      network.complete({'households': []});
      await tester.pump();
    },
  );

  for (final status in [406, 429, 500, 503]) {
    testWidgets(
      'cached detail remains readable when refresh fails with HTTP $status',
      (tester) async {
        final network = Completer<Map<String, dynamic>>();
        await tester.pumpWidget(
          MaterialApp(
            home: RecipeDetail(
              householdId: '1',
              recipeId: '9',
              title: 'Soup',
              cachedRequest: (_) async => {
                'recipe': {
                  'id': '9',
                  'title': 'Soup',
                  'description': 'Saved directions',
                },
              },
              request: (_) => network.future,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Saved directions'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        network.completeError(ApiException(status, 'Server unavailable'));
        await tester.pumpAndSettle();
        expect(find.text('Saved directions'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('cached detail remains usable when full request never returns', (
    tester,
  ) async {
    final network = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '1',
          recipeId: '9',
          title: 'Soup',
          cachedRequest: (_) async => {
            'recipe': {
              'id': '9',
              'title': 'Soup',
              'description': 'Saved directions',
            },
          },
          request: (_) => network.future,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Saved directions'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Saved directions'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    network.complete({'recipe': {}});
    await tester.pump();
  });

  testWidgets('confirmed access denial removes cached recipe detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '1',
          recipeId: '9',
          title: 'Soup',
          cachedRequest: (_) async => {
            'recipe': {
              'id': '9',
              'title': 'Soup',
              'description': 'Saved directions',
            },
          },
          request: (_) async => throw ApiException(403, 'Access denied'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved directions'), findsNothing);
    expect(find.text('Access denied'), findsOneWidget);
  });
  testWidgets('temporary refresh failure keeps loaded recipe visible', (
    tester,
  ) async {
    var fail = false;
    offlineStatus.value = false;
    addTearDown(() => offlineStatus.value = false);
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '1',
          recipeId: '1',
          title: 'Soup',
          request: (_) async {
            if (fail) throw ApiException(503, 'Temporary server failure');
            return {
              'recipe': {
                'id': '1',
                'title': 'Soup',
                'description': 'Keep this recipe readable.',
              },
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep this recipe readable.'), findsOneWidget);
    fail = true;
    offlineStatus.value = true;
    offlineStatus.value = false;
    await tester.pump();
    expect(find.text('Keep this recipe readable.'), findsOneWidget);
    expect(find.text('Temporary server failure'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
