import 'package:coffey_table_recipes/src/cooking_sessions.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite.dart';

import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/local_sqlite.dart';

Map<String, dynamic> library({
  String title = 'Soup',
  String date = '2026-11-07',
}) => {
  'schema': 1,
  'household_id': '1',
  'categories': [],
  'edit_options': {},
  'recipes': [
    {'id': '1', 'title': title},
  ],
  'responses': {
    '/households/1/recipes/1': {
      'recipe': {
        'id': '1',
        'title': title,
        'steps': [],
        'ingredients': [],
        'category_assignments': [],
      },
    },
    '/households/1/meal-plan': {
      'revision': 0,
      'today': '2026-11-06',
      'entries': [
        {
          'id': 'meal',
          'kind': 'recipe',
          'recipe_id': '1',
          'title': title,
          'plan_date': date,
        },
      ],
    },
    '/households/1/restaurants': {'items': []},
    '/households/1/recipes/1/favorites': {
      'people': [
        {'id': 'p', 'favorite': false},
      ],
      'current_person_id': 'p',
    },
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalSqlite db;
  late LocalData local;
  var online = false;
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>) deliver =
      (_, _) async => {};
  LocalData open() => LocalData(
    key: 'alice',
    fetch: (_) async => throw StateError('No network read expected'),
    send: (p, b) => deliver(p, b),
    readStore: db.read,
    writeStore: db.write,
  )..connected = () => online;
  setUp(() async {
    online = false;
    dir = await Directory.systemTemp.createTemp('ctr-sqlite-');
    db = LocalSqlite(
      factory: sqliteFactory,
      path: '${dir.path}/data.sqlite',
      readLegacy: (_) async => null,
    );
    local = open();
    await local.installSnapshot(library());
    await local.acceptShopping('1', {
      'revision': 0,
      'departments': ['Other'],
      'items': [
        {'id': 'milk', 'name': 'Milk', 'checked': false, 'department': 'Other'},
      ],
    });
  });
  tearDown(() async {
    local.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  test('meal moves are local immediately, survive restart and discard uses current server data', () async {
    await local.save('/households/1/meal-plan', {
      'operation': 'move',
      'id': 'meal',
      'date': '2026-11-09',
    });
    expect(
      (await local.request(
        '/households/1/meal-plan',
      ))['entries'][0]['plan_date'],
      '2026-11-09',
    );
    local.dispose();
    await db.close();
    local = open();
    expect(
      (await local.request(
        '/households/1/meal-plan',
      ))['entries'][0]['plan_date'],
      '2026-11-09',
    );
    expect(
      local.decisions.single['description'],
      contains('Soup from 2026-11-07 to 2026-11-09'),
    );
    await local.installSnapshot(library(date: '2026-11-08'));
    expect(
      (await local.request(
        '/households/1/meal-plan',
      ))['entries'][0]['plan_date'],
      '2026-11-09',
    );
    await local.decide(local.decisions.single['id'] as String, false);
    expect(
      (await local.request(
        '/households/1/meal-plan',
      ))['entries'][0]['plan_date'],
      '2026-11-08',
    );
  });
  test('offline recipes are visible in browsing and detail across restart and decisions do not upload themselves', () async {
    final added = await local.save('/households/1/recipes', {
      'title': 'Bread',
      'ingredients': [],
      'steps': [],
      'category_assignments': [],
    });
    await local.save('/households/1/recipes/1', {'title': 'My soup'});
    final id = added['recipe']['id'];
    local.dispose();
    await db.close();
    local = open();
    final recipes =
        (await local.request('/households/1/recipes'))['recipes'] as List;
    expect(recipes.map((r) => r['title']), containsAll(['Bread', 'My soup']));
    expect(
      (await local.request('/households/1/recipes/$id'))['recipe']['title'],
      'Bread',
    );
    final sent = <String>[];
    deliver = (p, b) async {
      sent.add(p);
      return {
        'recipe': {...b, 'id': '2'},
      };
    };
    online = true;
    await local.synchronize();
    expect(sent, ['/households/1/recipes']);
    await local.installSnapshot(library(title: 'Their soup'));
    expect(
      (await local.request('/households/1/recipes/1'))['recipe']['title'],
      'My soup',
    );
    await local.decide(local.decisions.single['id'] as String, false);
    expect(
      (await local.request('/households/1/recipes/1'))['recipe']['title'],
      'Their soup',
    );
  });
  test('online saves do not wait for server acknowledgement; shopping, favorites and restaurants are local offline', () async {
    final held = Completer<Map<String, dynamic>>();
    deliver = (_, _) => held.future;
    online = true;
    await local
        .save('/households/1/meal-plan', {
          'operation': 'move',
          'id': 'meal',
          'date': '2026-11-10',
        })
        .timeout(const Duration(seconds: 2));
    expect(
      (await local.request(
        '/households/1/meal-plan',
      ))['entries'][0]['plan_date'],
      '2026-11-10',
    );
    expect(local.decisions, isEmpty);
    online = false;
    await local.save('/households/1/recipes/1/favorites', {
      'person_id': 'p',
      'favorite': true,
    });
    expect(
      (await local.request(
        '/households/1/recipes/1/favorites',
      ))['people'].single['favorite'],
      true,
    );

    await local.save('/households/1/shopping-list', {
      'items': [
        {
          'id': 'bread',
          'name': 'Bread',
          'checked': true,
          'department': 'Other',
        },
      ],
    });
    await local.save('/households/1/restaurants', {
      'items': [
        {'id': 'r', 'name': 'Cafe'},
      ],
    });
    expect(
      (await local.request('/households/1/shopping-list'))['items'][0]['name'],
      'Bread',
    );
    expect(
      (await local.request('/households/1/restaurants'))['items'][0]['name'],
      'Cafe',
    );
    held.complete({});
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  test('shopping removals expire after two hours across restart and never replace another item', () async {
    var time = DateTime.utc(2026, 11, 6, 10);
    local.now = () => time;
    await local.save('/households/1/shopping-list', {
      'remove_ids': ['milk'],
    });
    await local.acceptShopping('1', {
      'revision': 1,
      'departments': ['Other'],
      'items': [
        {'id': 'milk', 'name': 'Milk'},
        {'id': 'new', 'name': 'Milk'},
      ],
    });
    expect(
      (await local.request(
        '/households/1/shopping-list',
      ))['items'].map((e) => e['id']),
      ['new'],
    );
    local.dispose();
    await db.close();
    local = open()..now = () => time;
    time = time.add(const Duration(hours: 2));
    await local.expire();
    expect(
      (await local.request('/households/1/shopping-list'))['items'],
      hasLength(2),
    );
  });
  test('existing file data and retained offline actions import into SQLite without being cleared', () async {
    final old = LocalSqlite(
      factory: sqliteFactory,
      path: '${dir.path}/old.sqlite',
      readLegacy: (key) async {
        if (key.startsWith('local-first-v1-')) {
          return jsonEncode({
            'data': {
              '/households/1/recipes/1': {
                'recipe': {'id': '1', 'title': 'Old'},
              },
            },
          });
        }
        return jsonEncode([
          {
            'id': 'retained',
            'kind': 'recipe',
            'path': '/households/1/recipes/1',
            'create': false,
            'body': {'title': 'Unsent'},
          },
        ]);
      },
    );
    final migrated = LocalData(
      key: 'alice',
      fetch: (_) async => {},
      send: (_, _) async => {},
      readStore: old.read,
      writeStore: old.write,
    );
    expect(
      (await migrated.request('/households/1/recipes/1'))['recipe']['title'],
      'Unsent',
    );
    migrated.dispose();
    await old.close();
    final again = LocalData(
      key: 'alice',
      fetch: (_) async => {},
      send: (_, _) async => {},
      readStore: old.read,
      writeStore: old.write,
    );
    expect(
      (await again.request('/households/1/recipes/1'))['recipe']['title'],
      'Unsent',
    );
    expect(again.decisions, hasLength(1));
    again.dispose();
    await old.close();
  });
  test(
    'cooking starts and step changes work locally offline and survive restart',
    () async {
      final service = CookingSessions(
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        request: (p, {body}) async => throw StateError('No server expected'),
      );
      await service.bindLocal(local, 'alice');
      final recipe = {
        'id': '1',
        'title': 'Soup',
        'ingredients': [],
        'groups': [],
        'steps': [
          {'id': 's', 'instruction': 'Simmer'},
        ],
        'actions': [],
      };
      final session = await service.create('1', recipe);
      await service.check('${session['id']}', 's', true);
      expect(service.sessions.single['completed'], ['s']);
      service.dispose();
      local.dispose();
      await db.close();
      local = open();
      expect(
        (await local.request(
          '/me/cooking-sessions',
        ))['sessions'].single['completed'],
        ['s'],
      );
    },
  );
  test('shopping attachments are available locally and delivered before the item that uses them', () async {
    const path = '/households/1/shopping-list';
    final photo = await local.save('$path/photos', {
      'image_base64': 'aW1hZ2U=',
    });
    await local.save(path, {
      'items': [
        {
          'id': 'attached',
          'name': 'Picture',
          'checked': false,
          'department': 'Other',
          'photo': photo['photo'],
        },
      ],
    });
    expect(
      (await local.request('$path/photos/${photo['photo']}'))['image_base64'],
      'aW1hZ2U=',
    );
    final serverPhoto = List.filled(64, 'b').join();
    var itemDelivered = false;
    deliver = (p, b) async {
      if (p.endsWith('/photos')) return {'photo': serverPhoto};
      expect(b['upsert_items'][0]['photo'], serverPhoto);
      itemDelivered = true;
      await local.acceptShopping('1', {
        'revision': 0,
        'departments': ['Other'],
        'items': b['upsert_items'],
      });
      return {};
    };
    online = true;
    await local.synchronize();
    await local.synchronize();
    expect(itemDelivered, true);
    expect((await local.request(path))['items'].single['photo'], serverPhoto);
  });
}
