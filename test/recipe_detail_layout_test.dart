import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_shopping_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 900.0]) {
    testWidgets('recipe actions fit below photo at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '1',
            recipeId: '7',
            title: 'Homemade Hamburger Buns',
            request: (path) async => path.endsWith('/favorites')
                ? {'people': []}
                : {
                    'recipe': {
                      'id': '7',
                      'title': 'Homemade Hamburger Buns',
                      'variation_family': [
                        {'id': '7', 'title': 'Homemade Hamburger Buns'},
                        {'id': '8', 'title': 'Whole wheat buns'},
                      ],
                      'description': 'Soft, tender hamburger buns.',
                      'photos': [
                        {'url': '', 'attribution': 'Marie'},
                      ],
                      'tags': [
                        {'label': 'Yeast Breads'},
                      ],
                      'ingredients': [
                        {'ingredient_name': 'Milk'},
                      ],
                      'steps': [
                        {'instruction': 'Mix.'},
                      ],
                    },
                  },
            save: (_, _) async => {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Homemade Hamburger Buns'), findsOneWidget);
      final photo = find.byType(RecipePhotoGallery);
      final cook = find.widgetWithText(FilledButton, 'Start cooking');
      final plan = find.widgetWithText(OutlinedButton, 'Add to meal plan');
      final favorite = find.byTooltip('Favorite (hold for household)');
      expect(
        tester.getBottomLeft(photo).dy,
        lessThan(tester.getTopLeft(cook).dy),
      );
      expect(tester.getCenter(cook).dy, tester.getCenter(plan).dy);
      final title = tester.getRect(find.text('Homemade Hamburger Buns'));
      final heart = tester.getRect(
        find.ancestor(of: favorite, matching: find.byType(IconButton)),
      );
      final variations = tester.getRect(
        find.byTooltip('Choose a recipe variation'),
      );
      expect(heart.top, title.top);
      expect(title.right, lessThanOrEqualTo(heart.left));
      expect(variations.top, greaterThanOrEqualTo(title.bottom));
      expect(variations.left, title.left);
      expect(
        variations.bottom,
        lessThan(
          tester.getTopLeft(find.text('Soft, tender hamburger buns.')).dy,
        ),
      );
      expect(tester.getRect(cook).right, lessThan(tester.getRect(plan).left));
      expect(tester.getRect(plan).right, lessThanOrEqualTo(width - 24));
      expect(tester.getRect(favorite).right, lessThanOrEqualTo(width - 24));
      expect(find.text('Request variation'), findsNothing);
      expect(
        tester.getCenter(find.text('Ingredients')).dy,
        tester.getCenter(find.text('Add to list')).dy,
      );
      await tester.tap(find.byTooltip('Recipe actions'));
      await tester.pumpAndSettle();
      for (final action in [
        'Edit recipe',
        'Share recipe',
        'Request variation',
        'Delete recipe',
      ]) {
        expect(find.text(action), findsOneWidget);
      }
      Navigator.of(tester.element(find.text('Share recipe'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to list'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeShoppingSelector), findsOneWidget);
      expect(find.text('Milk'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
