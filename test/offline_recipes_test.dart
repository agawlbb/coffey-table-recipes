import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/offline_store_io.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> disk;
  late List<String> fetched;
  var connected = true;
  var failDetail = false;
  const root = '/households/1/recipes';
  final rows = List.generate(
    31,
    (i) => {'id': '${i + 1}', 'title': 'Recipe ${i + 1}', 'photo_url': null},
  );
  Future<Map<String, dynamic>> server(String path) async {
    fetched.add(path);
    if (!connected) throw http.ClientException('No internet');
    final uri = Uri.parse(path);
    if (path == '/me') {
      return {
        'households': [
          {'id': '1', 'name': 'Our table'},
        ],
      };
    }
    if (path.endsWith('/people')) return {'people': []};
    if (uri.path == root) {
      final scope = uri.queryParameters['scope'];
      if (uri.queryParameters['tree'] == '1' && scope != '20') {
        return {
          'view': 'categories',
          'recipes': [],
          'next_offset': null,
          'category_nodes': [
            {
              'id': scope == null ? '10' : '20',
              'label': scope == null ? 'Meals' : 'Soups',
            },
          ],
        };
      }
      final offset = int.tryParse(uri.queryParameters['offset'] ?? '0') ?? 0;
      final available = scope == '20' ? rows.take(1).toList() : rows;
      return {
        'view': 'recipes',
        'category_nodes': [],
        'recipes': available.skip(offset).take(30).toList(),
        'next_offset': offset + 30 < available.length ? offset + 30 : null,
      };
    }
    if (failDetail && path == '$root/2') {
      throw TimeoutException('Disconnected during sync');
    }
    return {
      'recipe': {
        'id': uri.pathSegments.last,
        'title': 'Recipe ${uri.pathSegments.last}',
        'ingredients': [
          {
            'ingredient_name': uri.pathSegments.last == '1'
                ? 'Carrot'
                : 'Potato',
          },
        ],
        'tags': [
          {'kind': 'cuisine', 'label': 'French'},
        ],
        'steps': [
          {'instruction': 'Simmer until ready.'},
        ],
      },
    };
  }

  OfflineRecipes cache({String key = 'account-a', OfflineRequest? fetch}) =>
      OfflineRecipes(
        key: key,
        fetch: fetch ?? server,
        read: (key) async => disk[key],
        write: (key, value) async {
          disk[key] = value;
        },
      );

  setUp(() {
    disk = {};
    fetched = [];
    connected = true;
    failDetail = false;
    offlineStatus.value = false;
  });
  tearDown(() {
    offlineStatus.value = false;
  });

  test('detaching retains public family links without returning detached browse rows', () async {
    final c = cache();
    await c.sync(['1']);
    await c.rememberSavedRecipe('$root/2', {
      'recipe': {
        'id': '2',
        'title': 'Local variation',
        'parent_recipe_id': '1',
        'family_representative_id': '1',
        'in_household': true,
        'variation_family': [
          {'id': '1', 'title': 'Original', 'in_household': true},
          {'id': '2', 'title': 'Local variation', 'in_household': true},
          {'id': '99', 'title': 'Outside sibling', 'in_household': false},
        ],
        'related': [
          {'id': '1', 'relationship': 'parent'},
        ],
      },
    });
    await c.rememberSavedRecipe('$root/1/delete', {
      'deleted_recipe_id': '1',
      'purge_after': null,
    });
    connected = false;
    offlineStatus.value = true;
    final detail = (await c.request('$root/2'))['recipe'];
    expect(
      (detail['variation_family'] as List).map((r) => r['id']),
      containsAll(['1', '99']),
    );
    expect((detail['variation_family'] as List).first['in_household'], false);
    final grouped = (await c.request('$root?families=1'))['recipes'] as List;
    expect(grouped.any((r) => r['id'] == '2'), true);
    expect(grouped.any((r) => r['id'] == '1' || r['id'] == '99'), false);
    c.close();
  });

  testWidgets(
    'live ingredient search uses the synced library with no network requests',
    (tester) async {
      final c = cache();
      await c.sync(['1']);
      fetched.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeBrowser(
            householdId: '1',
            householdName: 'Our table',
            request: c.request,
            cachedRequest: c.cachedBrowse,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Meals'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'carrot');
      await tester.pumpAndSettle();
      expect(find.text('Recipe 1'), findsOneWidget);
      expect(find.text('Recipe 2'), findsNothing);
      expect(find.text('Meals'), findsNothing);
      expect(fetched, isEmpty);
      await tester.enterText(find.byType(TextField), 'no matching ingredient');
      await tester.pumpAndSettle();
      expect(find.text('Recipe 1'), findsNothing);
      expect(
        find.text('No recipes found in this scope. Try another search.'),
        findsOneWidget,
      );
      expect(fetched, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.close();
    },
  );

  test(
    'saved browse text is available online without a network fetch',
    () async {
      final c = cache();
      await c.sync(['1']);
      fetched.clear();
      final data = await c.cachedBrowse('$root?tree=1&scope=20');
      expect(data, isNotNull);
      expect(fetched, isEmpty);
      expect(await c.cachedBrowse('$root/1'), isNull);
      c.close();
    },
  );

  test('confirmed deletion removes offline text and restore returns it immediately', () async {
    final c = cache();
    await c.sync(['1']);
    final detail = await server('$root/1');
    await c.rememberSavedRecipe('$root/1/delete', {'deleted_recipe_id': '1'});
    connected = false;
    offlineStatus.value = true;
    expect(
      (await c.request(
        '$root?offset=0',
      ))['recipes'].any((row) => row['id'] == '1'),
      isFalse,
    );
    await expectLater(c.request('$root/1'), throwsA(isA<ApiException>()));
    await c.rememberSavedRecipe('$root/1/restore', detail);
    expect((await c.request('$root/1'))['recipe']['id'], '1');
    expect(
      (await c.request(
        '$root?offset=30',
      ))['recipes'].any((row) => row['id'] == '1'),
      isTrue,
    );
    c.close();
  });

  test('variation preview cannot replace the cached original or add an unsaved draft', () async {
    final c = cache();
    addTearDown(c.close);
    await c.sync(['1']);
    for (final id in [null, '1']) {
      await c.rememberSavedRecipe('$root/1/variation', {
        'questions': [],
        'recipe': {
          'id': id,
          'title': 'Unsaved variation',
          'parent_recipe_id': '1',
        },
      });
    }
    connected = false;
    offlineStatus.value = true;
    expect((await c.request('$root/1'))['recipe']['title'], 'Recipe 1');
    final firstPage = (await c.request('$root?offset=0'))['recipes'] as List;
    expect(
      firstPage.any((row) => row['title'] == 'Unsaved variation'),
      isFalse,
    );
    expect(firstPage.every((row) => row['id'] != null), isTrue);
  });

  test(
    'approved variation is immediately available offline under its own id',
    () async {
      final c = cache();
      addTearDown(c.close);
      await c.sync(['1']);
      await c.rememberSavedRecipe(root, {
        'recipe': {
          'id': '32',
          'title': 'Approved variation',
          'parent_recipe_id': '1',
          'is_variation': true,
        },
      });
      connected = false;
      offlineStatus.value = true;
      expect(
        (await c.request('$root/32'))['recipe']['title'],
        'Approved variation',
      );
      expect((await c.request('$root/1'))['recipe']['title'], 'Recipe 1');
      final results = (await c.request('$root?q=Approved'))['recipes'] as List;
      expect(results.single['id'], '32');
      expect(results.single['parent_recipe_id'], '1');
      expect(results.single['is_variation'], isTrue);
      final grouped =
          (await c.request('$root?families=1&offset=0'))['recipes'] as List;
      expect(grouped.any((row) => row['id'] == '32'), isFalse);
      expect(grouped.any((row) => row['id'] == '1'), isTrue);
      final foundFamily =
          (await c.request('$root?families=1&q=Approved'))['recipes'] as List;
      expect(foundFamily.single['id'], '1');
      expect(
        (await c.request('$root/32'))['recipe']['title'],
        'Approved variation',
      );
    },
  );

  test('Recently Deleted never falls back to offline cached data', () async {
    final c = cache(
      fetch: (path) async {
        if (!connected) throw http.ClientException('No internet');
        return {'recipes': [], 'next_offset': null};
      },
    );
    await c.request('$root/deleted?offset=0');
    connected = false;
    await expectLater(
      c.request('$root/deleted?offset=0'),
      throwsA(isA<http.ClientException>()),
    );
    c.close();
  });

  test(
    'deletion during sync cannot put an old detail back in the cache',
    () async {
      final waiting = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final c = cache(
        fetch: (path) async {
          if (path == '$root/1') {
            started.complete();
            return waiting.future;
          }
          return server(path);
        },
      );
      final sync = c.sync(['1']);
      await started.future;
      await c.rememberSavedRecipe('$root/1/delete', {'deleted_recipe_id': '1'});
      waiting.complete(await server('$root/1'));
      await sync;
      connected = false;
      offlineStatus.value = true;
      await expectLater(c.request('$root/1'), throwsA(isA<ApiException>()));
      c.close();
    },
  );

  test('sync fetches all pages and unvisited details; restart works without internet', () async {
    final first = cache();
    await first.request('/me');
    await first.sync(['1']);
    expect(fetched, contains('$root?offset=30'));
    expect(fetched, contains('$root/31'));
    first.close();
    connected = false;
    final restarted = cache();
    expect((await restarted.request('/me'))['households'], hasLength(1));
    expect(offlineStatus.value, isTrue);
    final before = fetched.length;
    expect(
      (await restarted.request(
        '$root/31',
      ))['recipe']['steps'][0]['instruction'],
      'Simmer until ready.',
    );
    expect(
      (await restarted.request(
        '$root?tree=1&q=&offset=0',
      ))['category_nodes'][0]['label'],
      'Meals',
    );
    expect(
      (await restarted.request(
        '$root?tree=1&scope=10',
      ))['category_nodes'][0]['label'],
      'Soups',
    );
    expect(
      (await restarted.request('$root?tree=1&scope=20'))['recipes'],
      hasLength(1),
    );
    expect((await restarted.request('$root?offset=0'))['next_offset'], 30);
    expect(
      (await restarted.request('$root?offset=30'))['recipes'],
      hasLength(1),
    );
    expect(fetched.length, before);
    restarted.close();
  });

  test(
    'offline search matches ingredients, tags and categories within scope',
    () async {
      final c = cache();
      await c.sync(['1']);
      offlineStatus.value = true;
      expect(
        (await c.request('$root?tree=1&q=carrot'))['recipes'],
        hasLength(1),
      );
      expect(
        (await c.request('$root?tree=1&q=FRENCH&scope=20'))['recipes'],
        hasLength(1),
      );
      expect(
        (await c.request('$root?tree=1&q=potato&scope=20'))['recipes'],
        isEmpty,
      );
      expect(
        (await c.request('$root?tree=1&q=soups'))['recipes'],
        hasLength(1),
      );
      c.close();
    },
  );

  test('a second account cannot read another account cache', () async {
    await cache().sync(['1']);
    offlineStatus.value = true;
    await expectLater(
      cache(key: 'account-b').request('$root/1'),
      throwsA(isA<ApiException>()),
    );
  });

  test('full text is saved before categories; metadata failures cannot block recipes', () async {
    final c = cache(
      fetch: (path) async {
        if (Uri.parse(path).queryParameters['tree'] == '1' ||
            path.endsWith('/people')) {
          throw ApiException(500, 'Metadata unavailable');
        }
        return server(path);
      },
    );
    await c.request('/me');
    await c.sync(['1']);
    expect(c.progress.value.ready, isTrue);
    expect(c.progress.value.saved, 31);
    connected = false;
    offlineStatus.value = true;
    final restarted = cache();
    for (var id = 1; id <= 31; id++) {
      expect(
        (await restarted.request(
          '$root/$id',
        ))['recipe']['steps'][0]['instruction'],
        'Simmer until ready.',
      );
    }
    expect(
      (await restarted.request('$root?tree=1&q=&offset=0'))['recipes'],
      hasLength(30),
    );
  });

  test('closing during initial download preserves the first batch and resumes missing text', () async {
    final reachedSecondBatch = Completer<void>();
    final blocked = Completer<Map<String, dynamic>>();
    final c = cache(
      fetch: (path) async {
        if (path == '$root/4') {
          reachedSecondBatch.complete();
          return blocked.future;
        }
        return server(path);
      },
    );
    await c.request('/me');
    final sync = c.sync(['1']);
    await reachedSecondBatch.future;
    expect(c.progress.value.saved, 3);
    expect(c.progress.value.ready, isFalse);
    c.close();
    blocked.complete(await server('$root/4'));
    await sync;
    connected = false;
    offlineStatus.value = true;
    final offline = cache();
    expect((await offline.request('$root/3'))['recipe']['id'], '3');
    expect((await offline.request('$root?tree=1'))['recipes'], hasLength(3));
    connected = true;
    offlineStatus.value = false;
    fetched.clear();
    final resumed = cache();
    await resumed.sync(['1']);
    expect(fetched, isNot(contains('$root/1')));
    expect(fetched, isNot(contains('$root/3')));
    expect(fetched, contains('$root/4'));
    expect(resumed.progress.value.ready, isTrue);
  });

  test('one failed detail does not discard other downloads and retry only fetches missing text', () async {
    final c = cache(
      fetch: (path) async {
        if (path == '$root/2') {
          throw ApiException(500, 'Temporary server error');
        }
        return server(path);
      },
    );
    await c.sync(['1']);
    expect(c.progress.value.ready, isFalse);
    expect(c.progress.value.saved, 30);
    fetched.clear();
    final resumed = cache();
    await resumed.sync(['1']);
    expect(fetched, contains('$root/2'));
    expect(fetched, isNot(contains('$root/31')));
    expect(resumed.progress.value.ready, isTrue);
  });

  test('completion requires a successful disk write, and a failed commit can be retried', () async {
    var failCommit = true;
    final c = OfflineRecipes(
      key: 'account-a',
      fetch: server,
      read: (key) async => disk[key],
      write: (key, value) async {
        final snapshot = jsonDecode(value) as Map;
        if (failCommit &&
            (snapshot['libraries'] as Map).containsKey('1') &&
            (snapshot['pending'] as Map).isEmpty) {
          throw StateError('Disk full');
        }
        disk[key] = value;
      },
    );
    await c.sync(['1']);
    expect(c.progress.value.ready, isFalse);
    expect(c.progress.value.error, contains('Could not save'));
    failCommit = false;
    fetched.clear();
    await c.sync(['1']);
    expect(c.progress.value.ready, isTrue);
    expect(fetched, isNot(contains('$root/1')));
    offlineStatus.value = true;
    expect((await cache().request('$root/31'))['recipe']['id'], '31');
  });

  test('an old completion timestamp does not skip repairing missing recipe details', () async {
    await cache().sync(['1']);
    final snapshot = jsonDecode(disk['account-a']!) as Map;
    (snapshot['responses'] as Map).remove('$root/31');
    disk['account-a'] = jsonEncode(snapshot);
    fetched.clear();
    final repaired = cache();
    await repaired.sync(['1']);
    expect(fetched, contains('$root/31'));
    expect(repaired.progress.value.ready, isTrue);
  });

  test('a recently completed cache still downloads newly added recipes on the next launch', () async {
    await cache().sync(['1']);
    fetched.clear();
    final added = [
      ...rows,
      {'id': '32', 'title': 'Recipe 32', 'photo_url': null},
    ];
    final nextLaunch = cache(
      fetch: (path) async {
        final uri = Uri.parse(path);
        if (uri.path == root &&
            uri.queryParameters['scope'] == null &&
            uri.queryParameters['tree'] != '1') {
          fetched.add(path);
          final offset = int.parse(uri.queryParameters['offset'] ?? '0');
          return {
            'recipes': added.skip(offset).take(30).toList(),
            'next_offset': offset + 30 < added.length ? offset + 30 : null,
          };
        }
        return server(path);
      },
    );
    await nextLaunch.sync(['1']);
    expect(fetched, contains('$root/32'));
    expect(fetched, isNot(contains('$root/31')));
    expect(nextLaunch.progress.value.total, 32);
    expect(nextLaunch.progress.value.ready, isTrue);
    offlineStatus.value = true;
    expect((await cache().request('$root/32'))['recipe']['id'], '32');
  });

  test(
    'native disk storage survives replacement and a new cache instance',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'offline-recipes-',
      );
      addTearDown(() async {
        final target = await directory.resolveSymbolicLinks();
        final parent = await Directory.systemTemp.resolveSymbolicLinks();
        expect(
          target,
          startsWith('$parent${Platform.pathSeparator}offline-recipes-'),
        );
        await Directory(target).delete(recursive: true);
      });
      const key = 'https://coffeybean.com/CoffeyTableRecipes/api/v1|account-a';
      final store = OfflineFileStore(directory: () async => directory);
      final c = OfflineRecipes(
        key: key,
        fetch: server,
        read: store.read,
        write: store.write,
      );
      await c.request('/me');
      await c.sync(['1']);
      expect(c.progress.value.ready, isTrue);
      c.close();
      connected = false;
      offlineStatus.value = true;
      final newStore = OfflineFileStore(directory: () async => directory);
      final reopened = OfflineRecipes(
        key: key,
        fetch: server,
        read: newStore.read,
        write: newStore.write,
      );
      expect((await reopened.request('/me'))['households'], hasLength(1));
      expect(
        (await reopened.request(
          '$root/31',
        ))['recipe']['steps'][0]['instruction'],
        'Simmer until ready.',
      );
    },
  );

  for (final status in [401, 403, 404, 500]) {
    test('HTTP $status is surfaced instead of stale cache', () async {
      final initial = cache();
      await initial.request('$root/1');
      final failing = cache(
        fetch: (_) async => throw ApiException(status, 'Denied'),
      );
      await expectLater(
        failing.request('$root/1'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', status)),
      );
      if (status != 500) {
        offlineStatus.value = true;
        await expectLater(
          cache().request('$root/1'),
          throwsA(isA<ApiException>()),
        );
      }
    });
  }

  test('interrupted sync preserves the last complete index', () async {
    await cache().sync(['1']);
    final source = jsonDecode(disk['account-a']!) as Map<String, dynamic>;
    source['libraries']['1']['synced_at'] = '2020-01-01T00:00:00Z';
    disk['account-a'] = jsonEncode(source);
    failDetail = true;
    await cache().sync(['1']);
    expect(offlineStatus.value, isTrue);
    expect(
      (await cache().request('$root?scope=20&tree=1'))['recipes'],
      hasLength(1),
    );
    expect((await cache().request('$root/31'))['recipe']['id'], '31');
  });

  test(
    'successful sync avoids downloading entire database again within a day',
    () async {
      await cache().sync(['1']);
      fetched.clear();
      await cache().sync(['1']);
      expect(fetched, contains('$root?offset=0'));
      expect(
        fetched.where((path) => Uri.parse(path).path.startsWith('$root/')),
        isEmpty,
      );
    },
  );

  test(
    'updated membership purges removed households from persistent cache',
    () async {
      await cache().sync(['1']);
      await cache(fetch: (_) async => {'households': []}).request('/me');
      offlineStatus.value = true;
      await expectLater(
        cache().request('$root/1'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('nonrecipe sensitive endpoints never use offline fallback', () async {
    await cache().request('/admin/accounts');
    connected = false;
    await expectLater(
      cache().request('/admin/accounts'),
      throwsA(isA<http.ClientException>()),
    );
  });

  test(
    'an in-flight sync cannot restore recipes after membership is removed',
    () async {
      final reachedDetail = Completer<void>();
      final detail = Completer<Map<String, dynamic>>();
      final c = cache(
        fetch: (path) async {
          if (path == '$root/1') {
            reachedDetail.complete();
            return detail.future;
          }
          if (path == '/me') return {'households': []};
          return server(path);
        },
      );
      final sync = c.sync(['1']);
      await reachedDetail.future;
      await c.request('/me');
      detail.complete({
        'recipe': {'id': '1'},
      });
      await sync;
      offlineStatus.value = true;
      await expectLater(
        cache().request('$root/1'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('broken storage does not prevent online recipe reads', () async {
    final c = OfflineRecipes(
      key: 'broken',
      fetch: server,
      read: (_) async => '{invalid',
      write: (_, _) async => throw StateError('Disk full'),
    );
    expect((await c.request('$root/1'))['recipe']['id'], '1');
  });

  testWidgets('offline badge is small and disappears when connection returns', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: OfflineIndicator(),
          ),
        ),
      ),
    );
    expect(find.text('Offline'), findsNothing);
    offlineStatus.value = true;
    await tester.pump();
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(tester.getSize(find.text('Offline')).height, lessThan(25));
    offlineStatus.value = false;
    await tester.pump();
    expect(find.text('Offline'), findsNothing);
  });

  testWidgets('reconnection refreshes browsing while preserving search', (
    tester,
  ) async {
    offlineStatus.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '1',
          householdName: 'Our table',
          request: server,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'carrot');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final before = fetched.length;
    offlineStatus.value = false;
    await tester.pumpAndSettle();
    expect(fetched.length, greaterThan(before));
    expect(Uri.parse(fetched.last).queryParameters['q'], 'carrot');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'carrot',
    );
  });

  testWidgets(
    'an unvisited recipe displays its text offline without any downloaded photos',
    (tester) async {
      final c = cache();
      await c.request('/me');
      await c.sync(['1']);
      expect(fetched, isNot(contains('/photo')));
      connected = false;
      offlineStatus.value = true;
      final restarted = cache();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '1',
            recipeId: '31',
            title: 'Recipe 31',
            request: restarted.request,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ingredients'), findsOneWidget);
      expect(find.textContaining('Simmer until ready.'), findsOneWidget);
      expect(find.text('Start cooking'), findsOneWidget);
      expect(find.textContaining('not been saved'), findsNothing);
    },
  );

  testWidgets(
    'completion status distinguishes partial, failed and fully saved text at phone width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final status = ValueNotifier(
        const RecipeSyncProgress(saved: 3, total: 31, working: true),
      );
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecipeSyncStatus(progress: status, retry: () => retries++),
          ),
        ),
      );
      expect(find.text('Preparing recipes for offline use…'), findsOneWidget);
      expect(find.textContaining('3 of 31'), findsNothing);
      expect(find.textContaining('All 31'), findsNothing);
      status.value = const RecipeSyncProgress(
        saved: 3,
        total: 31,
        error: 'Download paused',
      );
      await tester.pump();
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
      status.value = const RecipeSyncProgress(
        saved: 31,
        total: 31,
        ready: true,
      );
      await tester.pump();
      expect(find.text('All 31 recipes saved offline'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
