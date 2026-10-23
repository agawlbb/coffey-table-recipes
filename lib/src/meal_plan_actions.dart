import 'package:flutter/material.dart';

import 'api.dart';
import 'recipe_browser.dart';
import 'recipe_editor.dart';
import 'shopping_item_id.dart';

String mealPlanDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

Future<void> addUnscheduledMeal(
  BuildContext context, {
  required String householdId,
  required Map<String, dynamic> recipe,
  required RecipeRequest request,
  required RecipeSave save,
  VoidCallback? viewPlan,
}) async {
  try {
    final path = '/households/$householdId/meal-plan';
    final date = mealPlanDate(DateTime.now());
    final state = await request('$path?from=$date&to=$date');
    await save(path, {
      'revision': state['revision'],
      'operation': 'add',
      'id': newShoppingItemId(),
      'kind': 'recipe',
      'recipe_id': '${recipe['id']}',
      'date': null,
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Added to meal plan'),
        action: viewPlan == null
            ? null
            : SnackBarAction(label: 'View plan', onPressed: viewPlan),
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : 'Could not confirm the addition. Check the meal plan before trying again.',
          ),
          action: viewPlan == null
              ? null
              : SnackBarAction(label: 'View plan', onPressed: viewPlan),
        ),
      );
    }
  }
}
