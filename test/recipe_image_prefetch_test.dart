import 'package:coffey_table_recipes/src/recipe_image_prefetch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'warms all family and linked photos once without following their links',
    () async {
      final loaded = <String>[];
      final cached = <String>[];
      await prefetchRecipeImages(
        recipe: {
          'id': '1',
          'photos': [
            {'source_url': 'https://images.test/cover'},
          ],
          'variation_family': [
            {'id': '1'},
            {'id': '2'},
          ],
          'related': [
            {'id': '2'},
          ],
          'pairings': [
            {'id': '3'},
            {'id': '2'},
          ],
        },
        active: () => true,
        loadRecipe: (id) async {
          loaded.add(id);
          return {
            'id': id,
            'photos': [
              {'source_url': 'https://images.test/cover'},
              {'source_url': 'https://images.test/$id/a'},
              {'source_url': 'https://images.test/$id/b'},
              {'source_url': 'file:///private/photo'},
            ],
            'pairings': [
              {'id': '99'},
            ],
          };
        },
        cacheImage: (url) async => cached.add(url),
      );
      expect(loaded, ['2', '3']);
      expect(cached, [
        'https://images.test/cover',
        'https://images.test/2/a',
        'https://images.test/2/b',
        'https://images.test/3/a',
        'https://images.test/3/b',
      ]);
    },
  );

  test(
    'continues after inaccessible recipes and failed image downloads',
    () async {
      final cached = <String>[];
      await prefetchRecipeImages(
        recipe: {
          'id': '1',
          'pairings': [
            {'id': '2'},
            {'id': '3'},
          ],
        },
        active: () => true,
        loadRecipe: (id) async {
          if (id == '2') throw Exception('Unavailable');
          return {
            'photos': [
              {'source_url': 'https://images.test/fail'},
              {'source_url': 'https://images.test/ok'},
            ],
          };
        },
        cacheImage: (url) async {
          cached.add(url);
          if (url.endsWith('/fail')) throw Exception('Download failed');
        },
      );
      expect(cached, ['https://images.test/fail', 'https://images.test/ok']);
    },
  );

  test('stops queued work when the view closes or goes offline', () async {
    var active = true;
    final loaded = <String>[];
    await prefetchRecipeImages(
      recipe: {
        'id': '1',
        'variation_family': [
          {'id': '2'},
          {'id': '3'},
        ],
      },
      active: () => active,
      loadRecipe: (id) async {
        loaded.add(id);
        active = false;
        return {'photo_url': 'https://images.test/unused'};
      },
      cacheImage: (_) async => fail('Should not download after cancellation'),
    );
    expect(loaded, ['2']);
  });
}
