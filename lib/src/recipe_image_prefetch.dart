/// Warms images for one recipe, its family and explicitly linked recipes.
/// Related recipes are fetched once, without recursively walking their links.
Future<void> prefetchRecipeImages({
  required Map<String, dynamic> recipe,
  required Future<Map<String, dynamic>> Function(String id) loadRecipe,
  required Future<void> Function(String url) cacheImage,
  required bool Function() active,
}) async {
  final urls = <String>{};
  Future<void> warm(Map<String, dynamic> row) async {
    final images = [
      row['photo_url'],
      for (final photo in row['photos'] as List? ?? []) photo['source_url'],
    ];
    for (final value in images) {
      if (!active()) return;
      if (value is! String) continue;
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          !urls.add(value)) {
        continue;
      }
      try {
        await cacheImage(value);
      } catch (_) {
        // Best effort: one unavailable image must not stop the remaining photos.
      }
    }
  }

  await warm(recipe);
  final ids = <String>{recipe['id'].toString()};
  for (final key in ['variation_family', 'related', 'pairings']) {
    for (final row in recipe[key] as List? ?? []) {
      if (!active()) return;
      final id = row['id']?.toString();
      if (id == null || id.isEmpty || !ids.add(id)) continue;
      try {
        final related = await loadRecipe(id);
        if (active()) await warm(related);
      } catch (_) {
        // Deleted, inaccessible or offline recipes should not interrupt viewing.
      }
    }
  }
}
