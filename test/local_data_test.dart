import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

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
    Future<Map<String, dynamic>?> Function(String)? fallback,
  }) {
    final data = LocalData(
      key: key,
      fetch:
          fetch ??
          (path) async => Map<String, dynamic>.from(server[path] as Map),
      send: send ?? (path, body) async => throw TimeoutException('offline'),
      fallback: fallback,
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

  test(
    'shopping notes survive offline restart and upload with the entry',
    () async {
      final first = store();
      await first.request(list);
      final noted = {...item('Deodorant'), 'note': 'For Joe · 3 bottles'};
      await first.save(list, {
        'revision': 1,
        'items': [noted],
      });
      await settle(first);
      first.dispose();
      stores.remove(first);
      var uploaded = false;
      final restarted = store(
        send: (path, body) async {
          uploaded = true;
          expect(body['items'][0]['note'], 'For Joe · 3 bottles');
          return {'revision': 2, 'items': body['items'], 'departments': []};
        },
      );
      expect(
        (await restarted.cached(list))!['items'][0]['note'],
        'For Joe · 3 bottles',
      );
      await settle(restarted);
      expect(uploaded, isTrue);
    },
  );

  test(
    'optimistic meal persists selected cover before server acknowledgement',
    () async {
      const plan = '/households/1/meal-plan';
      final data = store(
        fetch: (path) async => path == recipe
            ? {
                'recipe': {
                  'id': '7',
                  'title': 'Cake',
                  'revision': 1,
                  'photos': [
                    {
                      'source_url': 'https://example.com/other.jpg',
                      'is_cover': false,
                    },
                    {
                      'source_url': 'https://example.com/cover.jpg',
                      'is_cover': true,
                    },
                  ],
                },
              }
            : {'revision': 1, 'today': '2026-10-23', 'entries': []},
      );
      await data.request(plan);
      await data.request(recipe);
      await data.save(plan, {
        'revision': 1,
        'operation': 'add',
        'id': 'meal',
        'kind': 'recipe',
        'recipe_id': '7',
        'date': '2026-10-24',
      });
      expect(
        (await data.cached(plan))!['entries'][0]['photo_url'],
        'https://example.com/cover.jpg',
      );
      final restarted = store();
      expect(
        (await restarted.cached(plan))!['entries'][0]['photo_url'],
        'https://example.com/cover.jpg',
      );
    },
  );
  test(
    'restaurants queue locally and outing name survives list removal',
    () async {
      const listPath = '/households/1/restaurants',
          plan = '/households/1/meal-plan';
      final data = store(
        fetch: (path) async => path == listPath
            ? {'revision': 0, 'items': []}
            : {'revision': 1, 'today': '2026-10-23', 'entries': []},
      );
      await data.request(listPath);
      await data.request(plan);
      await data.save(listPath, {
        'revision': 0,
        'items': [
          {'id': 'cafe', 'name': 'Cafe', 'logo_reference': null},
        ],
      });
      await data.save(plan, {
        'revision': 1,
        'operation': 'add',
        'id': 'outing',
        'kind': 'restaurant',
        'restaurant_id': 'cafe',
        'date': '2026-10-24',
      });
      await data.save(listPath, {'revision': 1, 'items': []});
      expect((await data.cached(plan))!['entries'][0]['title'], 'Cafe');
      expect((await data.cached(plan))!['entries'][0]['restaurant_id'], 'cafe');
    },
  );
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
      fetch: (_) async => throw ApiException(
        404, 'Household not found', code: 'household_not_found',
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
    test('${failure.code ?? "proxy"} read failure preserves household data', () async {
      final initial = store();
      await initial.request(list);
      await initial.request(recipe);
      await Future<void>.delayed(Duration.zero);
      final failing = store(fetch: (_) async => throw failure);
      await expectLater(
        failing.refresh(list, force: true), throwsA(same(failure)),
      );
      expect((await failing.cached(recipe))!['recipe']['title'], 'Soup');
      expect((await failing.cached(list))!['items'], hasLength(1));
      final restarted = store();
      expect((await restarted.cached(recipe))!['recipe']['title'], 'Soup');
    });
  }

  test('action denial preserves pending edits instead of archiving household', () async {
    final initial = store();
    await initial.request(list);
    await initial.request(recipe);
    await Future<void>.delayed(Duration.zero);
    final failing = store(send: (_, _) async => throw ApiException(
      403, 'Child mode', code: 'child_mode',
    ));
    await failing.save(list, {'revision': 1, 'items': [item('Bread')]});
    await settle(failing);
    expect(failing.pending, 1);
    expect(failing.archivedDrafts, isEmpty);
    expect(failing.conflicts.single['problem_code'], 'child_mode');
    expect((await failing.cached(list))!['items'][0]['name'], 'Bread');
    expect((await failing.cached(recipe))!['recipe']['title'], 'Soup');
  });

  test('invalid account response cannot erase memberships or cached recipes', () async {
    final initial = store();
    await initial.request(recipe);
    await Future<void>.delayed(Duration.zero);
    final failing = store(fetch: (_) async => {'status': 'temporarily unavailable'});
    await expectLater(
      failing.refresh('/me', force: true), throwsFormatException,
    );
    expect((await failing.cached(recipe))!['recipe']['title'], 'Soup');
  });

  test('confirmed account disable still revokes all local access', () async {
    final initial = store();
    await initial.request(recipe);
    await Future<void>.delayed(Duration.zero);
    final failing = store(fetch: (_) async => throw ApiException(
      403, 'Account disabled', code: 'account_disabled',
    ));
    await expectLater(
      failing.refresh(recipe, force: true), throwsA(isA<ApiException>()),
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

  test('successful membership refresh repairs legacy blocks and forces full download', () async {
    disk['local-first-v1-server|account'] = jsonEncode({
      'data': {'snapshot-version:1': 'old-version'},
      'aliases': {}, 'blocked': {'/households/1/': 403},
      'queue': [], 'archive': [],
    });
    final data = store(fetch: (_) async => {
      'households': [{'id': '1', 'name': 'Coffey'}],
    });
    await data.refresh('/me', force: true);
    await Future<void>.delayed(Duration.zero);
    expect(await data.snapshotVersion('1'), isNull);
    final saved = jsonDecode(disk['local-first-v1-server|account']!) as Map;
    expect(saved['blocked'], isEmpty);
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

  test(
    'lost creation response retries the same receipt without review',
    () async {
      final ids = <String>[];
      final data = store(
        send: (_, body) async {
          ids.add(body['client_save_id'] as String);
          if (ids.length == 1) throw TimeoutException('lost response');
          return {
            'recipe': {'id': '99', 'revision': '2', 'title': 'Local soup'},
          };
        },
      );
      final local = await data.save('/households/1/recipes', {
        'title': 'Local soup',
      });
      await settle(data);
      await data.synchronize();
      expect(ids.length, 2);
      expect(ids.toSet(), hasLength(1));
      expect(data.pending, 0);
      expect(data.conflicts, isEmpty);
      expect(
        (await data.cached(
          '/households/1/recipes/${local['recipe']['id']}',
        ))!['recipe']['id'],
        '99',
      );
    },
  );

  test('receipt-backed upload resumes after app closes during send', () async {
    final never = Completer<Map<String, dynamic>>();
    final first = store(send: (_, body) => never.future);
    final local = await first.save('/households/1/recipes', {'title': 'Soup'});
    await Future<void>.delayed(Duration.zero);
    final queued = jsonDecode(disk.values.single)['queue'][0];
    expect(queued['sending'], true);
    first.dispose();
    stores.remove(first);
    final second = store(
      send: (_, body) async {
        expect(body['client_save_id'], queued['body']['client_save_id']);
        return {
          'recipe': {'id': '81', 'revision': '2', 'title': 'Soup'},
        };
      },
    );
    await second.synchronize();
    expect(second.conflicts, isEmpty);
    expect(second.pending, 0);
    expect(
      (await second.cached(
        '/households/1/recipes/${local['recipe']['id']}',
      ))!['recipe']['id'],
      '81',
    );
  });

  testWidgets(
    'one-minute reminder survives restart and clears on confirmation',
    (tester) async {
      var clock = DateTime.utc(2026, 10, 23);
      var online = false;
      final reminders = <List<Map<String, dynamic>>>[];
      LocalData instance() {
        final data = LocalData(
          key: 'reminder-account',
          fetch: (_) async => {},
          send: (_, body) async => {
            'recipe': {'id': '90', 'revision': '2', 'title': body['title']},
          },
          now: () => clock,
          online: () => online,
          readStore: (key) async => disk[key],
          writeStore: (key, value) async {
            disk[key] = value;
          },
          onPendingChanged: (scope, changes) async {
            reminders.add(changes);
          },
        );
        stores.add(data);
        return data;
      }

      final first = instance();
      await first.save('/households/1/recipes', {'title': 'Offline soup'});
      await tester.pump();
      final deadline = reminders.last.single['deadline'];
      expect(deadline, clock.millisecondsSinceEpoch + 60000);
      clock = clock.add(const Duration(seconds: 59));
      await tester.pump(const Duration(seconds: 59));
      expect(first.overdue, 0);
      first.dispose();
      stores.remove(first);
      final second = instance();
      await second.cached('/households/1/recipes');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LocalSyncStatus(data: second)),
        ),
      );
      expect(reminders.last.single['deadline'], deadline);
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(second.overdue, 1);
      expect(find.textContaining('after one minute'), findsOneWidget);
      online = true;
      await second.synchronize();
      await tester.pump();
      expect(second.pending, 0);
      expect(reminders.last, isEmpty);
      expect(find.textContaining('after one minute'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'meal additions and moves require valid dates before queueing',
    () async {
      const root = '/households/1/meal-plan';
      final data = store(
        fetch: (_) async => {
          'revision': 1,
          'today': '2026-10-23',
          'entries': [],
        },
      );
      await data.request(root);
      for (final operation in ['add', 'move']) {
        for (final date in [null, '', '2026-02-31', 'not-a-date']) {
          await expectLater(
            data.save(root, {
              'revision': 1,
              'operation': operation,
              'id': 'meal',
              'kind': 'leftovers',
              'date': date,
            }),
            throwsA(
              isA<ApiException>().having(
                (error) => error.code,
                'code',
                'date_required',
              ),
            ),
          );
          expect(data.pending, 0);
          expect((await data.cached(root))!['entries'], isEmpty);
        }
      }
    },
  );

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
  test(
    'offline meal add move and remove survive restart and feed ingredients',
    () async {
      const root = '/households/1/meal-plan';
      final data = store(
        fetch: (path) async => path.startsWith(root)
            ? {'revision': 1, 'today': '2026-10-23', 'entries': []}
            : {
                'recipe': {
                  'id': '7',
                  'revision': '1',
                  'title': 'Soup',
                  'ingredients': [
                    {'ingredient_name': 'Carrot', 'quantity_decimal': 2},
                  ],
                  'pairings': [
                    {'id': '8', 'title': 'Bread'},
                  ],
                },
              },
      );
      await data.request('$root?from=2026-10-23&to=2026-10-25');
      await data.request(recipe);
      await data.save(root, {
        'revision': 1,
        'operation': 'add',
        'id': 'meal',
        'kind': 'recipe',
        'recipe_id': '7',
        'date': '2026-10-24',
      });
      final ingredients = await data.request(
        '$root/ingredients?from=2026-10-23&to=2026-10-25',
      );
      expect(ingredients['ingredients'][0]['ingredient_name'], 'Carrot');
      expect(
        (await data.request('$root/pairings/7'))['recipes'][0]['title'],
        'Bread',
      );
      await data.save(root, {
        'revision': 2,
        'operation': 'move',
        'id': 'meal',
        'date': '2026-11-01',
      });
      expect(
        (await data.request('$root?from=2026-10-23&to=2026-10-25'))['entries'],
        isEmpty,
      );
      await settle(data);
      data.dispose();
      stores.remove(data);
      final restarted = store();
      final future = await restarted.request(
        '$root?from=2026-11-01&to=2026-11-01',
      );
      expect(future['entries'][0]['title'], 'Soup');
      await restarted.save(root, {
        'revision': 3,
        'operation': 'remove',
        'id': 'meal',
      });
      expect(
        (await restarted.request(
          '$root?from=2026-11-01&to=2026-11-01',
        ))['entries'],
        isEmpty,
      );
      await settle(restarted);
      expect(restarted.pending, 3);
    },
  );

  test('first planner read downloads the full calendar once', () async {
    final calls = <String>[];
    final data = store(
      fetch: (path) async {
        calls.add(path);
        return {'revision': 0, 'entries': [], 'today': '2026-10-23'};
      },
    );
    await data.request('/households/1/meal-plan?from=2026-10-23&to=2026-10-24');
    final result = await data.request(
      '/households/1/meal-plan?from=2027-01-01&to=2027-01-31',
    );
    expect(result['entries'], isEmpty);
    expect(calls, ['/households/1/meal-plan?from=2000-01-01&to=2199-12-31']);
  });
  test('late authorized response cannot restore revoked data', () async {
    final seed = store();
    await seed.request(list);
    await Future<void>.delayed(Duration.zero);
    final response = Completer<Map<String, dynamic>>();
    final data = store(
      fetch: (path) async {
        if (path == list) return response.future;
        throw ApiException(
          404, 'Household not found', code: 'household_not_found',
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

  test('a denial in another household cannot revoke a late valid response', () async {
    final initial = store();
    await initial.request(list);
    await Future<void>.delayed(Duration.zero);
    final response = Completer<Map<String, dynamic>>();
    final data = store(fetch: (path) async {
      if (path == list) return response.future;
      throw ApiException(
        404, 'Household not found', code: 'household_not_found',
      );
    });
    final pending = data.refresh(list, force: true);
    await expectLater(
      data.refresh('/households/2/people', force: true),
      throwsA(isA<ApiException>()),
    );
    final rejected = expectLater(pending, throwsA(isA<ApiException>()));
    response.complete(server[list] as Map<String, dynamic>);
    await rejected;
    expect((await data.cached(list))!['items'][0]['name'], 'Milk');
  });

  test('creation receipt does not replace a later local recipe edit', () async {
    final creation = Completer<Map<String, dynamic>>();
    final edit = Completer<Map<String, dynamic>>();
    final data = store(
      send: (path, body) =>
          path.endsWith('/recipes') ? creation.future : edit.future,
    );
    const root = '/households/1/recipes';
    final original = await data.save(root, {'title': 'First soup'});
    final id = original['recipe']['id'];
    await data.save('$root/$id', {'title': 'Edited soup', 'revision': '1'});
    creation.complete({
      'recipe': {'id': '99', 'title': 'First soup', 'revision': '2'},
    });
    await Future<void>.delayed(Duration.zero);
    expect((await data.request('$root/$id'))['recipe']['title'], 'Edited soup');
    edit.complete({
      'recipe': {'id': '99', 'title': 'Edited soup', 'revision': '3'},
    });
    await settle(data);
    expect(data.pending, 0);
  });
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

  test(
    'an old read cannot roll back an already synchronized local edit',
    () async {
      final seed = store();
      await seed.request(list);
      await Future<void>.delayed(Duration.zero);
      final response = Completer<Map<String, dynamic>>();
      final data = store(
        fetch: (_) => response.future,
        send: (_, body) async => {
          'revision': 2,
          'items': body['items'],
          'departments': [],
        },
      );
      final old = data.refresh(list, force: true);
      await data.save(list, {
        'revision': 1,
        'items': [item('Bread')],
      });
      await settle(data);
      expect(data.pending, 0);
      response.complete(server[list] as Map<String, dynamic>);
      expect((await old)['items'][0]['name'], 'Bread');
      expect((await data.cached(list))!['items'][0]['name'], 'Bread');
    },
  );

  test(
    'local recipe identifiers are never requested from the backend',
    () async {
      var reads = 0;
      final delivery = Completer<Map<String, dynamic>>();
      final data = store(
        fetch: (_) async {
          reads++;
          throw ApiException(404, 'Unknown route');
        },
        send: (_, body) => delivery.future,
      );
      const root = '/households/1/recipes';
      final result = await data.save(root, {'title': 'Offline soup'});
      expect(
        (await data.request(
          '$root/${result['recipe']['id']}',
        ))['recipe']['title'],
        'Offline soup',
      );
      await Future<void>.delayed(Duration.zero);
      expect(reads, 0);
      delivery.complete({
        'recipe': {'id': '99', 'title': 'Offline soup', 'revision': '2'},
      });
      await settle(data);
    },
  );
  test(
    'local paired dishes are restricted to the household inventory',
    () async {
      server[recipe] = {
        'recipe': {
          'id': '7',
          'title': 'Soup',
          'pairings': [
            {'id': '8', 'title': 'Household bread'},
            {'id': '9', 'title': 'Unavailable dish'},
          ],
        },
      };
      final data = store(
        fallback: (path) async =>
            Uri.parse(path).path == '/households/1/recipes'
            ? {
                'recipes': [
                  {'id': '8', 'title': 'Household bread'},
                ],
                'next_offset': null,
              }
            : null,
      );
      await data.request(recipe);
      final result = await data.request('/households/1/meal-plan/pairings/7');
      expect((result['recipes'] as List).map((row) => row['id']), ['8']);
    },
  );
}
