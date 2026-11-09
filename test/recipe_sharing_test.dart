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
      '<a href="https://ctr.coffeybean.com/recipes/3">Fish &amp; &quot;Chips&quot; &lt;hot&gt;</a>',
    );
  });
  testWidgets('native rich sharing includes HTML and readable fallback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
          recipeId: 'local-soup',
          title: 'Old title',
          request: (_) async => {
            'recipe': {
              'id': '3',
              'title': 'Crêpes & cream',
              'original_language': 'fr',
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Recipe actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share recipe'));
    await tester.pumpAndSettle();
    expect(
      shared?.arguments['html'],
      '<a href="https://ctr.coffeybean.com/recipes/3">Crêpes &amp; cream</a>',
    );
    expect(
      shared?.arguments['text'],
      'Crêpes & cream\nhttps://ctr.coffeybean.com/recipes/3',
    );
    expect(shared?.arguments['origin'][2], greaterThan(0));
    expect(shared?.arguments['origin'][3], greaterThan(0));
    expect(find.text('Recipe link'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('unsynced recipe gives an accurate status without sharing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '2',
          recipeId: 'local-soup',
          title: 'Soup',
          request: (_) async => {
            'recipe': {'id': 'local-soup', 'title': 'Soup'},
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Recipe actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share recipe'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This recipe is waiting to sync. Share it once syncing finishes.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(tester.takeException(), isNull);
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
    const url = 'https://ctr.coffeybean.com/recipes/3';
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
    await tester.tap(find.byTooltip('Recipe actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share recipe'));
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
      await tester.tap(find.byTooltip('Recipe actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Copy HTML link'), findsNothing);
      expect(paths.length, 1);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('https://ctr.coffeybean.com/recipes/3'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Recipe actions'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.ancestor(
                of: find.text('Share recipe'),
                matching: find.byType(PopupMenuItem<String>),
              ),
            )
            .enabled,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
