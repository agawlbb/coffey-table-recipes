import 'snapshot_database_test.dart' show snapshot;

import 'dart:async';

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
      send: (path, body) async {
        if (send == null) throw TimeoutException('offline');
        final result = await send(path, body);
        return {
          ...result,
          if (body['client_change_id'] != null)
            'acknowledged_change_id': body['client_change_id'],
        };
      },
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

  test('damaged read cache cannot block fresh server state', () async {
    disk['local-first-v1-server|account'] = '{broken cache';
    final data = store();
    await data.acceptShopping('1', server[list] as Map<String, dynamic>);
    expect((await data.cached(list))!['items'], hasLength(1));
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
    'revoking a household removes its category metadata across restart',
    () async {
      final first = store();
      await first.installSnapshot(snapshot('Soup'));
      final denied = store(
        fetch: (_) async =>
            throw ApiException(404, 'Gone', code: 'household_not_found'),
      );
      await expectLater(
        denied.refresh('/households/1/people'),
        throwsA(isA<ApiException>()),
      );
      expect(await store().cached('/households/1/recipes?tree=1'), isNull);
    },
  );
  test('revoking one recipe does not hide a different recipe with the same ID prefix', () async {
    final first = store();
    await first.request(recipe);
    await first.acceptServerRecipe('/households/1/recipes/70', {
      'recipe': {'id': '70', 'title': 'Other'},
    });
    final denied = store(
      fetch: (_) async =>
          throw ApiException(404, 'Gone', code: 'recipe_not_found'),
    );
    await expectLater(denied.refresh(recipe), throwsA(isA<ApiException>()));
    expect(
      (await denied.cached('/households/1/recipes/70'))!['recipe']['title'],
      'Other',
    );
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
      fetch: (_) async => throw ApiException(
        404,
        'Household not found',
        code: 'household_not_found',
      ),
    );
    await expectLater(
      second.refresh(list, force: true),
      throwsA(isA<ApiException>()),
    );
    expect(await second.cached(list), isNull);
  });

  for (final failure in [
    ApiException(403, 'Child mode', code: 'child_mode'),
    ApiException(403, 'Administrator required', code: 'permission_denied'),
    ApiException(403, 'AI disabled', code: 'ai_images_disabled'),
    ApiException(403, 'Blocked by proxy'),
    ApiException(401, 'Sign in again', code: 'invalid_token'),
  ]) {
    test(
      '${failure.code ?? "proxy"} read failure preserves household data',
      () async {
        final initial = store();
        await initial.request(list);
        await initial.request(recipe);
        await Future<void>.delayed(Duration.zero);
        final failing = store(fetch: (_) async => throw failure);
        await expectLater(
          failing.refresh(list, force: true),
          throwsA(same(failure)),
        );
        expect((await failing.cached(recipe))!['recipe']['title'], 'Soup');
        expect((await failing.cached(list))!['items'], hasLength(1));
        final restarted = store();
        expect((await restarted.cached(recipe))!['recipe']['title'], 'Soup');
      },
    );
  }

  test(
    'invalid account response cannot erase memberships or cached recipes',
    () async {
      final initial = store();
      await initial.request(recipe);
      await Future<void>.delayed(Duration.zero);
      final failing = store(
        fetch: (_) async => {'status': 'temporarily unavailable'},
      );
      await expectLater(
        failing.refresh('/me', force: true),
        throwsFormatException,
      );
      expect((await failing.cached(recipe))!['recipe']['title'], 'Soup');
    },
  );

  test('confirmed account disable still revokes all local access', () async {
    final initial = store();
    await initial.request(recipe);
    await Future<void>.delayed(Duration.zero);
    final failing = store(
      fetch: (_) async =>
          throw ApiException(403, 'Account disabled', code: 'account_disabled'),
    );
    await expectLater(
      failing.refresh(recipe, force: true),
      throwsA(isA<ApiException>()),
    );
    expect(await failing.cached(recipe), isNull);
  });

  test('valid membership list still removes an absent household', () async {
    final initial = store();
    await initial.request(recipe);
    await Future<void>.delayed(Duration.zero);
    final data = store(fetch: (_) async => {'households': []});
    await data.refresh('/me', force: true);
    expect(await data.cached(recipe), isNull);
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

  test('late authorized response cannot restore revoked data', () async {
    final seed = store();
    await seed.request(list);
    await Future<void>.delayed(Duration.zero);
    final response = Completer<Map<String, dynamic>>();
    final data = store(
      fetch: (path) async {
        if (path == list) return response.future;
        throw ApiException(
          404,
          'Household not found',
          code: 'household_not_found',
        );
      },
    );
    final old = data.refresh(list, force: true);
    await expectLater(
      data.refresh('/households/1/people', force: true),
      throwsA(isA<ApiException>()),
    );
    final failed = expectLater(
      old,
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
    response.complete(server[list] as Map<String, dynamic>);
    await failed;
    expect(await data.cached(list), isNull);
  });

  test(
    'a denial in another household cannot revoke a late valid response',
    () async {
      final initial = store();
      await initial.request(list);
      await Future<void>.delayed(Duration.zero);
      final response = Completer<Map<String, dynamic>>();
      final data = store(
        fetch: (path) async {
          if (path == list) return response.future;
          throw ApiException(
            404,
            'Household not found',
            code: 'household_not_found',
          );
        },
      );
      final pending = data.refresh(list, force: true);
      await expectLater(
        data.refresh('/households/2/people', force: true),
        throwsA(isA<ApiException>()),
      );
      final accepted = expectLater(
        pending,
        completion(isA<Map<String, dynamic>>()),
      );
      response.complete(server[list] as Map<String, dynamic>);
      await accepted;
      expect((await data.cached(list))!['items'][0]['name'], 'Milk');
    },
  );

  test(
    'online deletion and restore update the local source immediately',
    () async {
      final data = store();
      await data.request(recipe);
      await data.acceptServerRecipe('$recipe/delete', {
        'deleted_recipe_id': '7',
      });
      expect(await data.cached(recipe), isNull);
      await data.acceptServerRecipe('$recipe/restore', {
        'recipe': {'id': '7', 'title': 'Restored soup', 'revision': '2'},
      });
      expect((await data.request(recipe))['recipe']['title'], 'Restored soup');
    },
  );
}
