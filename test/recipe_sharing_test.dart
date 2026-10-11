import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('send a link passes the server URL to native sharing', (
    tester,
  ) async {
    MethodCall? shared;
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      shared = call;
      return 'chosen.app';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    const url =
        'https://coffeybean.com/CoffeyTableRecipes/share.php?token=signed';
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '2',
          recipeId: '3',
          title: 'Crêpes',
          request: (path) async => path.endsWith('/share')
              ? {'url': url}
              : {
                  'recipe': {'title': 'Crêpes', 'original_language': 'fr'},
                },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send a link'));
    await tester.pumpAndSettle();
    expect(shared?.method, 'share');
    expect(shared?.arguments['text'], url);
    expect(shared?.arguments['originWidth'], greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('share offers send a link and reports server failures', (
    tester,
  ) async {
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '2',
          recipeId: '3',
          title: 'Crêpes',
          request: (path) async {
            paths.add(path);
            if (path.endsWith('/share')) {
              throw ApiException(503, 'Sharing is unavailable.');
            }
            return {
              'recipe': {'title': 'Crêpes', 'original_language': 'fr'},
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Send a link'), findsOneWidget);
    expect(
      find.text('Anyone with the link can view this recipe.'),
      findsOneWidget,
    );
    expect(paths.length, 1);
    await tester.tap(find.text('Send a link'));
    await tester.pumpAndSettle();
    expect(paths.last, '/households/2/recipes/3/share');
    expect(find.text('Sharing is unavailable.'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.share))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
