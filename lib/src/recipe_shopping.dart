import 'package:flutter/material.dart';

import 'api.dart';
import 'recipe_browser.dart';
import 'recipe_editor.dart';
import 'recipe_shopping_selector.dart';
import 'shopping_ingredient.dart';
import 'shopping_item_id.dart';

/// Both the recipe page and planner use the same selection and shopping writes.
Future<void> showRecipeShopping(
  BuildContext context, {
  required String householdId,
  required RecipeRequest request,
  required RecipeSave save,
  required List<ShoppingIngredient> ingredients,
  Future<List<ShoppingIngredient>?> Function(BuildContext)? onChooseDates,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: false,
  enableDrag: false,
  showDragHandle: true,
  clipBehavior: Clip.antiAlias,
  constraints: const BoxConstraints(maxWidth: 800),
  builder: (_) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .8,
    child: RecipeShoppingSelector(
      onChooseDates: onChooseDates,
      ingredients: ingredients.where((i) => i.name.isNotEmpty).toList(),
      loadExisting: () async => [
        for (final item in recipeRows(
          (await request('/households/$householdId/shopping-list'))['items'],
        ))
          '${item['name']}',
      ],
      onAdd: (names) async {
        final path = '/households/$householdId/shopping-list';
        final additions = [
          for (final name in names)
            {
              'id': newShoppingItemId(),
              'name': name,
              'department': '',
              'checked': false,
            },
        ];
        for (var attempt = 0; ; attempt++) {
          final current = await request(path);
          final items = recipeRows(current['items']);
          final ids = items.map((i) => i['id']).toSet();
          try {
            await save(path, {
              'revision': current['revision'],
              'items': [
                ...items,
                ...additions.where((i) => !ids.contains(i['id'])),
              ],
            });
            return;
          } on ApiException catch (error) {
            if (error.status != 409 || attempt >= 2) rethrow;
          }
        }
      },
    ),
  ),
);
