import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_category_selection.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const catalog = <Map<String, dynamic>>[
  {'id': '1', 'label': 'Desserts', 'parent_label': null},
  {'id': '2', 'label': 'Pies', 'parent_label': 'Desserts'},
  {'id': '3', 'label': 'Main Dish', 'parent_label': null},
];

void main() {
  test(
    'trusted IDs replace proposal metadata and self labels resolve to roots',
    () {
      final selected = <String, dynamic>{
        'category_id': '2',
        'label': 'Rejected',
        'parent_label': 'Desserts',
      };
      normalizeRecipeCategory(selected, catalog);
      expect(selected['category_id'], '2');
      expect(selected.containsKey('label'), isFalse);
      final root = <String, dynamic>{
        'label': ' main dish ',
        'parent_label': 'Main Dish',
      };
      normalizeRecipeCategory(root, catalog);
      expect(root['category_id'], '3');
      expect(root.containsKey('label'), isFalse);
      final proposal = <String, dynamic>{
        'label': 'New dessert',
        'parent_label': 'Desserts',
      };
      normalizeRecipeCategory(proposal, catalog);
      expect(proposal['label'], 'New dessert');
    },
  );
  test(
    'changing parent selects the root and removes the rejected proposal',
    () {
      final row = <String, dynamic>{
        'category_id': '2',
        'label': 'Rejected',
        'parent_label': 'Desserts',
        '_parent_category': 'Main Dish',
      };
      selectRecipeCategoryParent(row, catalog);
      expect(row['category_id'], '3');
      expect(row.containsKey('label'), isFalse);
      expect(row.containsKey('parent_label'), isFalse);
    },
  );
  for (final changeParent in [false, true]) {
    testWidgets(
      'replacing import proposal saves chosen ${changeParent ? 'parent' : 'child'} ID',
      (tester) async {
        Map<String, dynamic>? submitted;
        await tester.pumpWidget(
          MaterialApp(
            home: RecipeEditor(
              householdId: '2',
              recipe: {
                'title': 'Imported soup',
                'original_language': 'en',
                'measurement_system': 'us',
                'ingredients': <Map<String, dynamic>>[],
                'steps': <Map<String, dynamic>>[],
                'category_assignments': [
                  {'label': 'Rejected suggestion', 'parent_label': 'Desserts'},
                ],
                'edit_options': {'categories': catalog},
              },
              save: (_, body) async {
                submitted = body;
                throw ApiException(500, 'Captured save');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Recipe details'));
        final details = tester.widget<ExpansionTile>(
          find
              .ancestor(
                of: find.text('Recipe details'),
                matching: find.byType(ExpansionTile),
              )
              .first,
        );
        if (!details.controller!.isExpanded) {
          await tester.tap(find.text('Recipe details'));
        }
        await tester.pumpAndSettle();
        final dropdown = find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText ==
                  (changeParent ? 'Parent category' : 'Category'),
        );
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(changeParent ? 'Main Dish' : 'Pies').last);
        await tester.pumpAndSettle();
        expect(find.text('New category name'), findsNothing);
        await tester.tap(find.text('Save recipe'));
        await tester.pumpAndSettle();
        expect(submitted, isNotNull);
        final row = (submitted!['category_assignments'] as List).single as Map;
        expect(row['category_id'], changeParent ? '3' : '2');
        expect(row.containsKey('label'), isFalse);
        expect(row.containsKey('parent_label'), isFalse);
      },
    );
  }
}
