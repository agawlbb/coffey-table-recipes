import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/connection_indicator.dart';
import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'snapshot_database_test.dart' show snapshot;
import 'recipe_editor_test.dart' as fixtures;

Map<String, dynamic> pushed(String title) {
  final state = snapshot(title);
  state['responses']['/households/1/recipes/1'] = {
    'recipe': {...fixtures.recipe(), 'id': '1', 'title': title},
  };
  return state;
}

LocalData cache() => LocalData(
  key: 'push-authority',
  fetch: (_) async => throw StateError('Use pushed server data'),
  send: (_, _) async => {},
  readStore: (_) async => null,
  writeStore: (_, _) async {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => connectedHouseholds.value = {});
  testWidgets(
    'closing an editor displays the latest pushed recipe instead of an older save reply',
    (tester) async {
      final data = cache();
      addTearDown(data.dispose);
      await data.installSnapshot(pushed('Starting recipe'));
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '1',
            recipeId: '1',
            title: 'Starting recipe',
            request: data.request,
            localRead: data.readView,
            save: (path, body) async {
              await data.installSnapshot(pushed('Newer server edit'));
              return {
                'recipe': {...body, 'title': 'Older save reply'},
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Edit recipe'));
      await tester.tap(find.byTooltip('Edit recipe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Newer server edit'), findsWidgets);
      expect(find.text('Older save reply'), findsNothing);
      expect(
        data.readView('/households/1/recipes/1')['recipe']['title'],
        'Newer server edit',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a pushed deletion removes an open recipe while the connection remains green',
    (tester) async {
      final data = cache();
      addTearDown(data.dispose);
      connectedHouseholds.value = {'1'};
      await data.installSnapshot(pushed('Starting recipe'));
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '1',
            recipeId: '1',
            title: 'Starting recipe',
            request: data.request,
            localRead: data.readView,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gone = pushed('Gone');
      gone['recipes'] = [];
      (gone['responses'] as Map).remove('/households/1/recipes/1');
      (gone['responses'] as Map).remove('/households/1/recipes/1/favorites');
      await data.installSnapshot(gone);
      await tester.pumpAndSettle();
      expect(find.text('This recipe is no longer available.'), findsOneWidget);
      expect(find.byTooltip('Connected to server'), findsOneWidget);
      expect(
        () => data.readView('/households/1/recipes/1'),
        throwsA(isA<ApiException>()),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'an incomplete recipe snapshot cannot erase the last complete server data',
    () async {
      final data = cache();
      addTearDown(data.dispose);
      await data.installSnapshot(pushed('Complete server data'));
      final broken = pushed('Incomplete');
      (broken['responses'] as Map).remove('/households/1/recipes/1');
      await expectLater(data.installSnapshot(broken), throwsFormatException);
      expect(
        data.readView('/households/1/recipes/1')['recipe']['title'],
        'Complete server data',
      );
    },
  );
}
