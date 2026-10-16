import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_sharing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('coffey_table_recipes/share_link'),
          (call) async => false,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('coffey_table_recipes/share_link'),
          null,
        );
  });
  test('HTML recipe links escape titles and use the public rendered page', () {
    expect(
      recipeShareHtml('3', 'Fish & "Chips" <hot>'),
      '<a href="https://coffeybean.com/CoffeyTableRecipes/share.php?id=3">Fish &amp; &quot;Chips&quot; &lt;hot&gt;</a>',
    );
  });
  testWidgets('copy HTML link copies the named escaped anchor', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '2',
          recipeId: '3',
          title: 'Soup',
          request: (_) async => {
            'recipe': {'title': 'Soup & beans', 'original_language': 'en'},
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy HTML link'));
    await tester.pumpAndSettle();
    expect(
      copied,
      '<a href="https://coffeybean.com/CoffeyTableRecipes/share.php?id=3">Soup &amp; beans</a>',
    );
    expect(find.text('HTML link copied'), findsOneWidget);
  });

  testWidgets('native rich sharing includes HTML and readable fallback', (
    tester,
  ) async {
    MethodCall? shared;
    const channel = MethodChannel('coffey_table_recipes/share_link');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      shared = call;
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '2',
          recipeId: '3',
          title: 'Old title',
          request: (_) async => {
            'recipe': {'title': 'Crêpes & cream', 'original_language': 'fr'},
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send a link'));
    await tester.pumpAndSettle();
    expect(
      shared?.arguments['html'],
      '<a href="https://coffeybean.com/CoffeyTableRecipes/share.php?id=3">Crêpes &amp; cream</a>',
    );
    expect(
      shared?.arguments['text'],
      'Crêpes & cream\nhttps://coffeybean.com/CoffeyTableRecipes/share.php?id=3',
    );
    expect(find.text('Recipe link'), findsNothing);
  });

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
    const url = 'https://coffeybean.com/CoffeyTableRecipes/share.php?id=3';
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
    expect(shared?.arguments['text'], 'Crêpes\n$url');
    expect(shared?.arguments['originWidth'], greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'share offers a copyable link when native sharing is unavailable',
    (tester) async {
      final paths = <String>[];
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '2',
            recipeId: '3',
            title: 'Crêpes',
            request: (path) async {
              paths.add(path);
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
      expect(paths.length, 1);
      expect(find.text('Copy link'), findsOneWidget);
      expect(
        find.text('https://coffeybean.com/CoffeyTableRecipes/share.php?id=3'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.share))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
