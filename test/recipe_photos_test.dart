import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Orange Chicken responsive variants display once with cover preserved',
    () {
      const base = 'https://www.modernhoney.com/wp-content/uploads/2018/01/';
      final rows = [
        {'source_url': '${base}Chinese-Orange-Chicken-2.jpg', 'is_cover': 1},
        for (final size in ['500x500', '500x375', '480x270'])
          {
            'source_url': '${base}Chinese-Orange-Chicken-2-$size.jpg',
            'is_cover': 0,
          },
        {'source_url': '${base}Chinese-Orange-Chicken-3.jpg', 'is_cover': 0},
      ];
      final photos = distinctRecipePhotos(rows);
      expect(photos, hasLength(2));
      expect(photos.first['is_cover'], 1);
      expect(photos.first['source_url'], '${base}Chinese-Orange-Chicken-2.jpg');
      expect(rows, hasLength(5));
    },
  );
  test('unrelated filename dimensions are not collapsed', () {
    final photos = distinctRecipePhotos([
      {'source_url': 'https://example.com/photo.jpg'},
      {'source_url': 'https://example.com/photo-500x500.jpg'},
    ]);
    expect(photos, hasLength(2));
  });
  for (final height in [400.0, 900.0]) {
    testWidgets('whole photo fits inside viewport-bounded frame at $height', (
      tester,
    ) async {
      tester.view.physicalSize = Size(360, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RecipePhotoGallery(
              photos: [
                {'source_url': null, 'caption': 'First'},
                {'source_url': null, 'caption': 'Second'},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(PageView)).height,
        lessThanOrEqualTo(height * .3),
      );
      expect(
        tester.widget<RecipePhoto>(find.byType(RecipePhoto).first).fit,
        BoxFit.contain,
      );
      await tester.tap(find.byTooltip('Next photo'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
