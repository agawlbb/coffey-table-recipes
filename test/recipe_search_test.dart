import 'dart:async';

import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'typing uses saved results immediately and hides categories until cleared',
    (tester) async {
      final requested = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '2',
            householdName: 'Coffey',
            request: (path) async {
              requested.add(path);
              return {};
            },
            cachedRequest: (path) async {
              final q = Uri.parse(path).queryParameters['q'] ?? '';
              return {
                'category_nodes': [
                  {'id': '5', 'label': 'Breakfast', 'recipe_count': 2},
                ],
                'recipes': [
                  if (q.isEmpty || 'bran muffins'.contains(q))
                    {'id': '1', 'title': 'Bran muffins'},
                  if (q.isEmpty || 'pancakes'.contains(q))
                    {'id': '2', 'title': 'Pancakes'},
                ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Breakfast'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'bran');
      await tester.pump();
      expect(find.text('Breakfast'), findsNothing);
      expect(find.text('Bran muffins'), findsOneWidget);
      expect(find.text('Pancakes'), findsNothing);
      expect(requested, isEmpty);
      await tester.enterText(find.byType(TextField), 'panc');
      await tester.pump();
      expect(find.text('Pancakes'), findsOneWidget);
      expect(find.text('Bran muffins'), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Bran muffins'), findsOneWidget);
      expect(requested, isEmpty);
    },
  );

  testWidgets(
    'uncached typing coalesces requests and ignores a stale response',
    (tester) async {
      final paths = <String>[];
      final old = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '2',
            householdName: 'Coffey',
            request: (path) async {
              final q = Uri.parse(path).queryParameters['q'];
              paths.add(q ?? '');
              if (q == 'bran') return old.future;
              return {
                'recipes': [
                  if (q == 'panc') {'id': '2', 'title': 'Pancakes'},
                ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'b');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'br');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'bran');
      await tester.pump(const Duration(milliseconds: 300));
      expect(paths, ['', 'bran']);
      await tester.enterText(find.byType(TextField), 'panc');
      await tester.pumpAndSettle();
      expect(find.text('Pancakes'), findsOneWidget);
      old.complete({
        'recipes': [
          {'id': '1', 'title': 'Stale muffins'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Stale muffins'), findsNothing);
      expect(find.text('Pancakes'), findsOneWidget);
    },
  );
}
