import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/local_data.dart';

Map<String, dynamic> snapshot(String title, {String household = '1'}) {
  final root = '/households/$household';
  return {
    'schema': 1,
    'household_id': household,
    'version': title,
    'edit_options': {'categories': [], 'recipes': []},
    'recipes': [
      {'id': '1', 'title': title},
    ],
    'categories': [
      {'id': '10', 'parent_id': null, 'label': 'Meals'},
      {'id': '11', 'parent_id': '10', 'label': 'Soups'},
    ],
    'responses': {
      '$root/recipes/1': {
        'recipe': {
          'id': '1',
          'title': title,
          'revision': '1',
          'category_assignments': [
            {'category_id': '11'},
          ],
        },
      },
      '$root/recipes/1/favorites': {'people': []},
      '$root/people': {'people': []},
      '$root/shopping-list': {'revision': 1, 'items': []},
      '$root/recipe-blank': {
        'recipe': {'title': ''},
      },
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'complete snapshot survives restart; category reads never use network',
    () async {
      final disk = <String, String>{};
      var requests = 0;
      Future<Map<String, dynamic>> fetch(String _) async {
        requests++;
        throw StateError('Unexpected network');
      }

      LocalData local() => LocalData(
        key: 'local',
        fetch: fetch,
        send: (p, b) => fetch(p),
        snapshotOnly: true,
        readStore: (k) async => disk[k],
        writeStore: (k, v) async {
          disk[k] = v;
        },
      );
      var store = local();
      expect(await store.snapshotVersion('1'), isNull);
      await store.installSnapshot(snapshot('Soup'));
      store.dispose();
      store = local();
      expect(await store.snapshotVersion('1'), 'Soup');
      expect(await store.snapshotVersion('2'), isNull);
      final tree = await store.request(
        '/households/1/recipes?tree=1&families=1',
      );
      expect(
        (tree['category_nodes'] as List).first,
        isA<Map<String, dynamic>>(),
      );
      for (var i = 0; i < 3; i++) {
        final rows = await store.request('/households/1/recipes?scope=11');
        expect((rows['recipes'] as List).single['title'], 'Soup');
        expect(
          (await store.request('/households/1/recipes/1'))['recipe']['title'],
          'Soup',
        );
      }
      await store.installSnapshot(snapshot('New soup'));
      expect(
        ((await store.request('/households/1/recipes?scope=11'))['recipes']
                as List)
            .single['title'],
        'New soup',
      );
      expect(requests, 0);
      store.dispose();
    },
  );
  test(
    'failed persistence retains last completed database and version',
    () async {
      String? saved;
      var fail = false;
      final data = LocalData(
        key: 'test',
        snapshotOnly: true,
        fetch: (_) async => throw StateError('network'),
        send: (p, b) async => {},
        readStore: (_) async => saved,
        writeStore: (k, v) async {
          if (fail) throw StateError('full');
          saved = v;
        },
      );
      await data.installSnapshot(snapshot('Old'));
      fail = true;
      await expectLater(
        data.installSnapshot(snapshot('New')),
        throwsStateError,
      );
      expect(await data.snapshotVersion('1'), 'Old');
      expect(
        (await data.request('/households/1/recipes/1'))['recipe']['title'],
        'Old',
      );
      expect(jsonDecode(saved!)['data'], isNotNull);
      data.dispose();
    },
  );
  test(
    'snapshot replacement preserves pending local shopping changes',
    () async {
      final data = LocalData(
        key: 'pending',
        snapshotOnly: true,
        fetch: (_) async => throw StateError('network'),
        send: (p, b) async => throw StateError('offline'),
        readStore: (_) async => null,
        writeStore: (k, v) async {},
      );
      await data.installSnapshot(snapshot('Old'));
      await data.save('/households/1/shopping-list', {
        'revision': 1,
        'items': [
          {'id': 'i', 'name': 'Milk', 'checked': false, 'department': 'Other'},
        ],
      });
      await data.installSnapshot(snapshot('New'));
      expect(
        (await data.request(
          '/households/1/shopping-list',
        ))['items'].single['name'],
        'Milk',
      );
      expect(data.pending, 1);
      data.dispose();
    },
  );
  test('partial snapshot cannot make a household ready', () async {
    final data = LocalData(
      key: 'partial',
      snapshotOnly: true,
      fetch: (_) async => {},
      send: (p, b) async => {},
      readStore: (_) async => null,
      writeStore: (k, v) async {},
    );
    final partial = snapshot('Partial');
    (partial['responses'] as Map).remove('/households/1/recipes/1');
    await expectLater(data.installSnapshot(partial), throwsFormatException);
    expect(await data.snapshotVersion('1'), isNull);
    data.dispose();
  });
  testWidgets(
    'Android local browser paints root categories and stays responsive',
    (tester) async {
      var network = 0;
      final data = LocalData(
        key: 'android',
        snapshotOnly: true,
        fetch: (_) async {
          network++;
          throw StateError('network must not run');
        },
        send: (p, b) async => {},
        readStore: (_) async => null,
        writeStore: (k, v) async {},
      );
      await data.installSnapshot(snapshot('Soup'));
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '1',
            householdName: 'Table',
            localOnly: true,
            request: data.request,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Meals'), findsOneWidget);
      expect(find.text('Soup'), findsOneWidget);
      expect(find.textContaining('connection'), findsNothing);
      expect(find.byTooltip('Refresh recipes'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Meals'));
      await tester.pumpAndSettle();
      expect(find.text('Soups'), findsOneWidget);
      await tester.tap(find.text('Soups'));
      await tester.pumpAndSettle();
      expect(find.text('Soup'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recipe-breadcrumb-0')));
      await tester.pumpAndSettle();
      expect(find.text('Meals'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Soup');
      await tester.pumpAndSettle();
      expect(find.text('Soup'), findsWidgets);
      expect(network, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test('large local catalog does not perform category-squared scans for empty search', () async {
    final data = LocalData(
      key: 'catalog',
      snapshotOnly: true,
      fetch: (_) async => throw StateError('network'),
      send: (p, b) async => {},
      readStore: (_) async => null,
      writeStore: (k, v) async {},
    );
    final large = snapshot('Large');
    large['categories'] = [
      {'id': '10', 'parent_id': null, 'label': 'Meals'},
      for (var c = 0; c < 5000; c++)
        {'id': '${100 + c}', 'parent_id': '10', 'label': 'Category $c'},
    ];
    large['recipes'] = [
      for (var r = 1; r <= 200; r++) {'id': '$r', 'title': 'Recipe $r'},
    ];
    final responses = large['responses'] as Map;
    for (var r = 1; r <= 200; r++) {
      responses['/households/1/recipes/$r'] = {
        'recipe': {
          'id': '$r',
          'title': 'Recipe $r',
          'category_assignments': [
            {'category_id': '${99 + r}'},
          ],
        },
      };
      responses['/households/1/recipes/$r/favorites'] = {'people': []};
    }
    await data.installSnapshot(large);
    final timer = Stopwatch()..start();
    final page = await data.request('/households/1/recipes?tree=0&families=1');
    timer.stop();
    expect((page['recipes'] as List).length, 30);
    expect(timer.elapsed, lessThan(const Duration(seconds: 5)));
    data.dispose();
  });

  testWidgets(
    'local read failure leaves the hamburger menu and input responsive',
    (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            key: const ValueKey('local-error-scaffold'),
            appBar: AppBar(title: const Text('Recipes')),
            drawer: const Drawer(child: Text('Household navigation')),
            body: RecipeBrowser(
              householdId: '1',
              householdName: 'Table',
              embedded: true,
              localOnly: true,
              request: (_) async {
                reads++;
                throw StateError('Local test failure');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The local recipe database could not be read.'),
        findsOneWidget,
      );
      expect(find.textContaining('connection'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('Household navigation'), findsOneWidget);
      tester
          .state<ScaffoldState>(
            find.byKey(const ValueKey('local-error-scaffold')),
          )
          .closeDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Soup');
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Soup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
