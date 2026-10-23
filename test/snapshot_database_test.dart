import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
}
