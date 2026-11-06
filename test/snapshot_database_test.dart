import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/local_data.dart';

Map<String, dynamic> snapshot(String title, {String household = '1'}) {
  final root = '/households/$household';
  return {
    'schema': 1,
    'household_id': household,
    'household': {'id': household, 'name': 'Table', 'role': 'owner'},
    'user': {'id': '1', 'display_name': 'Alice', 'child_mode': false},
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

  test('household AI image permission reaches local edit options and updates with the snapshot', () async {
    final data = LocalData(
      key: 'permissions',
      fetch: (_) async => throw StateError('Unexpected network'),
      send: (_, _) async => throw StateError('Unexpected write'),
      readStore: (_) async => null,
      writeStore: (_, _) async {},
    );
    for (final enabled in [true, false, true]) {
      final source = snapshot('Soup-$enabled');
      source['edit_options'] = <String, dynamic>{
        ...source['edit_options'] as Map,
        'ai_images_enabled': enabled,
      };
      ((source['responses'] as Map)['/households/1/recipes/1']['recipe']
          as Map)['edit_options'] = {
        'ai_images_enabled': enabled,
      };
      await data.installSnapshot(source);
      final options = await data.request(
        '/households/1/recipes/1/edit-options',
      );
      expect(options['edit_options']['ai_images_enabled'], enabled);
      expect(
        data.readView(
          '/households/1/recipes/1',
        )['recipe']['edit_options']['ai_images_enabled'],
        enabled,
      );
    }
    data.dispose();
  });

  testWidgets(
    'Android local browser paints root categories and stays responsive',
    (tester) async {
      var network = 0;
      final data = LocalData(
        key: 'android',
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

  testWidgets(
    'iOS blank filtering and detail do not wait for background persistence',
    (tester) async {
      final saving = Completer<void>();
      var stall = false;
      var asynchronousReads = 0;
      final data = LocalData(
        key: 'ios-local',
        fetch: (_) async => throw StateError('Unexpected network'),
        send: (_, body) async => {},
        readStore: (_) async => null,
        writeStore: (_, value) async {
          if (stall) await saving.future;
        },
      );
      final first = snapshot('Local blank dish');
      (first['responses']
              as Map)['/households/1/recipes/1']['recipe']['source_type'] =
          'blank';
      await data.installSnapshot(first);
      stall = true;
      final background = data.installSnapshot(snapshot('Incoming change'));
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '1',
            householdName: 'Table',
            localOnly: true,
            localRead: data.readView,
            cachedRequest: (_) {
              asynchronousReads++;
              return Completer<Map<String, dynamic>?>().future;
            },
            request: (_) {
              asynchronousReads++;
              return Completer<Map<String, dynamic>>().future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blank recipes only'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Local blank dish'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('Local blank dish'));
      await tester.pumpAndSettle();
      expect(find.text('Local blank dish'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(asynchronousReads, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Local blank dish'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      saving.complete();
      await background;
      await tester.pumpAndSettle();
      expect(find.text('Incoming change'), findsWidgets);
      expect(asynchronousReads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

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
