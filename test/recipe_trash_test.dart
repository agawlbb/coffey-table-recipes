import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_trash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => offlineStatus.value = false);

  testWidgets(
    'deleted recipes show their recovery window and can be restored',
    (tester) async {
      var restored = false;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeTrash(
            householdId: '1',
            request: (path) async {
              expect(path, '/households/1/recipes/deleted?offset=0');
              return {
                'recipes': restored
                    ? []
                    : [
                        {
                          'id': '7',
                          'title': 'Soup',
                          'deleted_at': DateTime.now()
                              .toUtc()
                              .toIso8601String(),
                          'purge_after': DateTime.now()
                              .add(const Duration(days: 30))
                              .toUtc()
                              .toIso8601String(),
                        },
                      ],
                'next_offset': null,
              };
            },
            save: (path, body) async {
              expect(path, '/households/1/recipes/7/restore');
              restored = true;
              return {
                'recipe': {'id': '7'},
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('30 days left'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(restored, isTrue);
      expect(find.text('No recently deleted recipes.'), findsOneWidget);
    },
  );

  testWidgets('offline trash explains that a connection is required', (
    tester,
  ) async {
    offlineStatus.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeTrash(
          householdId: '1',
          request: (_) async => throw StateError('Should not fetch'),
          save: (_, _) async => throw StateError('Should not save'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Connect to the internet to view Recently Deleted.'),
      findsOneWidget,
    );
  });

  testWidgets('failed restoration keeps the recipe available for retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeTrash(
          householdId: '1',
          request: (_) async => {
            'recipes': [
              {
                'id': '7',
                'title': 'Soup',
                'deleted_at': DateTime.now().toUtc().toIso8601String(),
                'purge_after': DateTime.now()
                    .add(const Duration(days: 1))
                    .toUtc()
                    .toIso8601String(),
              },
            ],
          },
          save: (_, _) async =>
              throw ApiException(410, 'The 30-day recovery period has ended.'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Soup'), findsOneWidget);
    expect(find.text('The 30-day recovery period has ended.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deletion asks for confirmation and Undo restores with a fresh request',
    (tester) async {
      final paths = <String>[];
      var changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => RecipeDetail(
                      householdId: '1',
                      recipeId: '7',
                      title: 'Soup',
                      request: (_) async => {
                        'recipe': {
                          'id': '7',
                          'title': 'Soup',
                          'revision': '4',
                          'ingredients': [],
                          'steps': [],
                        },
                      },
                      onChanged: () => changed = true,
                      save: (path, body) async {
                        paths.add(path);
                        if (path.endsWith('/delete')) {
                          expect(body['revision'], '4');
                        }
                        return {};
                      },
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete recipe'));
      await tester.pumpAndSettle();
      expect(paths, isEmpty);
      expect(find.textContaining('restore it for 30 days'), findsOneWidget);
      await tester.tap(find.text('Delete recipe'));
      await tester.pumpAndSettle();
      expect(paths, ['/households/1/recipes/7/delete']);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(paths.last, '/households/1/recipes/7/restore');
      expect(changed, isTrue);
    },
  );
}
