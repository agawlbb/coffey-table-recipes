import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';

void main() {
  test(
    'viewed public recipe remains available after restart during an outage',
    () async {
      String? disk;
      final first = OfflineRecipes(
        key: 'public',
        fetch: (_) async => {
          'recipe': {'id': '1', 'title': 'Soup'},
        },
        read: (_) async => disk,
        write: (_, s) async {
          disk = s;
        },
      );
      await first.request('/recipes/1');
      first.close();
      final second = OfflineRecipes(
        key: 'public',
        fetch: (_) async => throw ApiException(503, 'offline'),
        read: (_) async => disk,
        write: (_, s) async {
          disk = s;
        },
      );
      expect((await second.request('/recipes/1'))['recipe']['title'], 'Soup');
      second.close();
    },
  );
  test(
    'public cache does not substitute saved data for a confirmed removal',
    () async {
      var missing = false;
      final cache = OfflineRecipes(
        key: 'public',
        fetch: (_) async {
          if (missing) throw ApiException(404, 'Removed');
          return {
            'recipe': {'id': '1', 'title': 'Soup'},
          };
        },
        read: (_) async => null,
        write: (_, s) async {},
      );
      await cache.request('/recipes/1');
      missing = true;
      await expectLater(
        cache.request('/recipes/1'),
        throwsA(isA<ApiException>()),
      );
      expect(await cache.cachedRead('/recipes/1'), isNull);
      cache.close();
    },
  );
}
