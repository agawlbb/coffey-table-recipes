import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:coffey_table_recipes/src/cooking_mode.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_design_test.dart' show TestUser;

void main() {
  for (final destination in ['browser', 'detail', 'cooking']) {
    testWidgets(
      'Recipes from $destination returns to root and clears every filter',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const channel = MethodChannel('coffey_table_recipes/timers');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'list' ? [] : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final paths = <String>[];
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
                if (path.endsWith('/people')) {
                  return {
                    'people': [
                      {'id': '10', 'display_name': 'Joe', 'user_id': '42'},
                    ],
                  };
                }
                if (path.endsWith('/favorites')) return {'people': []};
                final uri = Uri.parse(path);
                if (uri.path == '/households/2/recipes') {
                  paths.add(path);
                  final q = uri.queryParameters;
                  if (q['tree'] == '1' && !q.containsKey('scope')) {
                    return {
                      'view': 'categories',
                      'category_nodes': [
                        {'id': 'g', 'label': 'Meals', 'recipe_count': 1},
                      ],
                      'recipes': [],
                    };
                  }
                  return {
                    'recipes': [
                      {'id': '9', 'title': 'Soup'},
                    ],
                    'next_offset': null,
                  };
                }
                return {
                  'recipe': {
                    'id': '9',
                    'title': 'Soup',
                    'ingredients': [],
                    'steps': [
                      {'id': 's', 'position': 1, 'instruction': 'Stir.'},
                    ],
                  },
                };
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Meals'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'soup');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Filters'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Blank recipes only'));
        await tester.tap(find.text('Favorite'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Joe'));
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(Uri.parse(paths.last).queryParameters['blank'], '1');
        expect(Uri.parse(paths.last).queryParameters['favorite_people'], '10');
        if (destination != 'browser') {
          await tester.tap(find.text('Soup'));
          await tester.pumpAndSettle();
          expect(find.byType(RecipeDetail), findsOneWidget);
          expect(find.byTooltip('Open navigation menu'), findsOneWidget);
          if (destination == 'cooking') {
            await tester.tap(find.text('Start cooking'));
            await tester.pumpAndSettle();
            expect(find.byType(CookingMode), findsOneWidget);
            expect(find.byTooltip('Open navigation menu'), findsOneWidget);
          }
        }
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Recipes'));
        await tester.pumpAndSettle();
        expect(find.byType(RecipeDetail), findsNothing);
        expect(find.byType(CookingMode), findsNothing);
        expect(find.text('Meals'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(find.byTooltip('Filters'), findsOneWidget);
        final query = Uri.parse(paths.last).queryParameters;
        expect(query['q'], '');
        expect(query.containsKey('scope'), isFalse);
        expect(query.containsKey('blank'), isFalse);
        expect(query.containsKey('favorite_people'), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
