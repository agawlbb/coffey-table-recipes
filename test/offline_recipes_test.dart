import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
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
      expect(fetched, isEmpty);
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
}
