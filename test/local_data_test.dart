import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const list = '/households/1/shopping-list';
  const recipe = '/households/1/recipes/7';
  late Map<String, String> disk;
  late Map<String, dynamic> server;
  late List<LocalData> stores;
  LocalData store({
    LocalRead? fetch,
    LocalWrite? send,
    Future<void> Function(String, String)? write,
    String key = 'server|account',
  }) {
    final data = LocalData(
      key: key,
      fetch:
          fetch ??
          (path) async => Map<String, dynamic>.from(server[path] as Map),
      send: send ?? (path, body) async => throw TimeoutException('offline'),
      readStore: (key) async => disk[key],
      writeStore:
          write ??
          (key, value) async {
            disk[key] = value;
          },
    );
    stores.add(data);
    return data;
  }

  Future<void> settle(LocalData data) async {
    await Future<void>.delayed(Duration.zero);
    await data.synchronize();
  }

  Map<String, dynamic> item(String name) => {
    'id': 'item',
    'name': name,
    'checked': false,
    'department': '',
  };
  setUp(() {
    disk = {};
    stores = [];
    server = {
      list: {
        'revision': 1,
        'items': [item('Milk')],
        'departments': <String>[],
      },
      recipe: {
        'recipe': {
          'id': '7',
          'revision': '1',
          'title': 'Soup',
          'ingredients': [],
        },
      },
    };
  });
  tearDown(() {
    for (final data in stores) {
      data.dispose();
    }
  });

  test('restart reads local data while refresh never completes', () async {
    final first = store();
    await first.request(list);
    await Future<void>.delayed(Duration.zero);
    first.dispose();
    stores.remove(first);
    final never = Completer<Map<String, dynamic>>();
    final second = store(fetch: (_) => never.future);
    final saved = await second
        .request(list)
        .timeout(const Duration(seconds: 1));
    expect(saved['items'][0]['name'], 'Milk');
  });

  test(
    'offline edits are durable before returning and survive restart',
    () async {
      final first = store();
      await first.request(list);
      final result = await first.save(list, {
        'revision': 1,
        'items': [item('Bread')],
      });
      expect(result['revision'], 2);
      await settle(first);
      first.dispose();
      stores.remove(first);
      final second = store();
      expect((await second.request(list))['items'][0]['name'], 'Bread');
      expect(second.pending, 1);
      expect(jsonDecode(disk.values.single)['queue'], hasLength(1));
    },
  );

  test(
    'pending local changes cannot be replaced by a stale network response',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final data = store();
      await data.request(list);
      await Future<void>.delayed(Duration.zero);
      final other = store(fetch: (_) => response.future);
      await other.cached(list);
      final refresh = other.refresh(list, force: true);
      await other.save(list, {
        'revision': 1,
        'items': [item('Bread')],
      });
      response.complete(server[list] as Map<String, dynamic>);
      expect((await refresh)['items'][0]['name'], 'Bread');
      expect((await other.request(list))['items'][0]['name'], 'Bread');
    },
  );

  test('queue serializes two edits against successive revisions', () async {
    final sent = <int>[];
    final response = Completer<Map<String, dynamic>>();
    final data = store(
      send: (_, body) async {
        sent.add(body['revision'] as int);
        if (sent.length == 1) return response.future;
        return {'revision': 3, 'items': body['items'], 'departments': []};
      },
    );
    await data.request(list);
    await data.save(list, {
      'revision': 1,
      'items': [item('Bread')],
    });
    await Future<void>.delayed(Duration.zero);
    await data.save(list, {
      'revision': 2,
      'items': [item('Butter')],
    });
    response.complete({
      'revision': 2,
      'items': [item('Bread')],
      'departments': [],
    });
    await settle(data);
    expect(sent, [1, 2]);
    expect(data.pending, 0);
    expect((await data.cached(list))!['items'][0]['name'], 'Butter');
  });

  test('conflict retains draft without overwriting another device', () async {
    var sends = 0;
    final data = store(
      send: (_, body) async {
        sends++;
        throw ApiException(409, 'Changed by another member');
      },
    );
    await data.request(list);
    await data.save(list, {
      'revision': 1,
      'items': [item('Bread')],
    });
    await settle(data);
    await data.synchronize();
    expect(sends, 1);
    expect(data.conflicts, hasLength(1));
    expect((await data.request(list))['items'][0]['name'], 'Bread');
    await data.keepServer(data.conflicts.single['id'] as String);
    expect((await data.cached(list))!['items'][0]['name'], 'Milk');
    expect(jsonDecode(disk.values.single)['archive'], hasLength(1));
  });

  test('failed device storage never acknowledges an offline edit', () async {
    var broken = false;
    final data = store(
      write: (key, value) async {
        if (broken) throw StateError('disk full');
        disk[key] = value;
      },
    );
    await data.request(list);
    await Future<void>.delayed(Duration.zero);
    broken = true;
    await expectLater(
      data.save(list, {
        'revision': 1,
        'items': [item('Bread')],
      }),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 507)),
    );
    expect(data.pending, 0);
    expect((await data.cached(list))!['items'][0]['name'], 'Milk');
  });

  test('accounts and servers never share stored data', () async {
    final first = store();
    await first.request(list);
    await Future<void>.delayed(Duration.zero);
    final second = store(key: 'another-server|another-account');
    expect(await second.cached(list), isNull);
  });

  test('access revocation removes local household data', () async {
    final first = store();
    await first.request(list);
    await Future<void>.delayed(Duration.zero);
    final second = store(
      fetch: (_) async => throw ApiException(403, 'Access removed'),
    );
    await expectLater(
      second.refresh(list, force: true),
      throwsA(isA<ApiException>()),
    );
    expect(await second.cached(list), isNull);
  });

  test(
    'new recipe is visible locally and aliases resolve after sync',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final data = store(send: (_, body) => response.future);
      const root = '/households/1/recipes';
      final local = await data.save(root, {
        'title': 'Local soup',
        'ingredients': [],
      });
      final id = local['recipe']['id'];
      expect('$id', startsWith('local-'));
      expect(
        (await data.request('$root/$id'))['recipe']['title'],
        'Local soup',
      );
      expect((await data.request('$root?q=soup'))['recipes'], hasLength(1));
      response.complete({
        'recipe': {'id': '99', 'title': 'Local soup', 'revision': '2'},
      });
      await settle(data);
      expect((await data.request('$root/$id'))['recipe']['id'], '99');
    },
  );

  test('uncertain recipe creation is not automatically replayed', () async {
    var sends = 0;
    final data = store(
      send: (_, body) async {
        sends++;
        throw TimeoutException('lost response');
      },
    );
    await data.save('/households/1/recipes', {'title': 'Local soup'});
    await settle(data);
    await data.synchronize();
    expect(sends, 1);
    expect(data.conflicts.single['problem'], contains('response was lost'));
  });

  test(
    'full plan snapshot serves different ranges without a network wait',
    () async {
      const root = '/households/1/meal-plan';
      final data = store(
        fetch: (_) async => {
          'revision': 1,
          'today': '2026-10-23',
          'entries': [
            {'id': 'a', 'plan_date': null},
            {'id': 'b', 'plan_date': '2026-10-24'},
            {'id': 'c', 'plan_date': '2026-11-01'},
          ],
        },
      );
      await data.request('$root?from=2000-01-01&to=2199-12-31');
      final range = await data.cached('$root?from=2026-10-23&to=2026-10-25');
      expect((range!['entries'] as List).map((e) => e['id']), ['a', 'b']);
    },
  );
  test(
    'reviewed conflict reapplies local content to the displayed revision',
    () async {
      var conflict = true;
      final revisions = <int>[];
      final data = store(
        send: (_, body) async {
          revisions.add(body['revision'] as int);
          if (conflict) throw ApiException(409, 'Changed on another device');
          return {'revision': 4, 'items': body['items'], 'departments': []};
        },
      );
      await data.request(list);
      await data.save(list, {
        'revision': 1,
        'items': [item('Bread')],
      });
      await settle(data);
      conflict = false;
      await data.useLocal(data.conflicts.single['id'] as String, {
        'revision': 3,
        'items': [item('Milk')],
        'departments': [],
      });
      expect(revisions, [1, 3]);
      expect((await data.cached(list))!['items'][0]['name'], 'Bread');
      expect(data.archivedDrafts, hasLength(1));
    },
  );

  test('one conflict does not block independent edits', () async {
    final sent = <String>[];
    final data = store(
      send: (path, body) async {
        sent.add(path);
        if (path == list) throw ApiException(409, 'Changed');
        return {
          'recipe': {...body, 'id': '7', 'revision': '2'},
        };
      },
    );
    await data.request(list);
    await data.request(recipe);
    await data.save(list, {
      'revision': 1,
      'items': [item('Bread')],
    });
    await data.save(recipe, {'revision': '1', 'title': 'New soup'});
    await settle(data);
    expect(sent, containsAll([list, recipe]));
    expect(data.pending, 1);
    expect((await data.cached(recipe))!['recipe']['title'], 'New soup');
  });

  test('favorites are durable idempotent local changes', () async {
    const path = '$recipe/favorites';
    server[path] = {
      'current_person_id': '2',
      'people': [
        {'id': '2', 'favorite': false},
      ],
    };
    final data = store();
    await data.request(path);
    await data.save(path, {'favorite': true});
    await settle(data);
    expect((await data.cached(path))!['people'][0]['favorite'], true);
    expect(data.pending, 1);
  });
}
