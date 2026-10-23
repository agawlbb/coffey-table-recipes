import 'dart:async';

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
  final selected = await confirmMealRecipe(context, recipe);
  if (selected == null || !context.mounted) return;
  final noticeEpoch = mealPlanNotices.epoch;
  try {
    final path = '/households/$householdId/meal-plan';
    final date = mealPlanDate(DateTime.now());
    final state = await request('$path?from=$date&to=$date');
    await save(path, {
      'revision': state['revision'],
      'operation': 'add',
      'id': newShoppingItemId(),
      'kind': 'recipe',
      'recipe_id': '${selected['id']}',
      'date': null,
    });
    if (!context.mounted || noticeEpoch != mealPlanNotices.epoch) return;
    mealPlanNotices.show(
      ScaffoldMessenger.of(context),
      SnackBar(
        duration: const Duration(seconds: 5),
        content: const Text('Added to meal plan'),
        action: viewPlan == null
            ? null
            : SnackBarAction(
                label: 'View plan',
                onPressed: () {
                  mealPlanNotices.dismiss();
                  viewPlan();
                },
              ),
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
              : SnackBarAction(
                  label: 'View plan',
                  onPressed: () {
                    mealPlanNotices.dismiss();
                    viewPlan();
                  },
                ),
        ),
      );
    }
  }
}

Future<Map<String, dynamic>?> confirmMealRecipe(
  BuildContext context,
  Map<String, dynamic> full, {
  String destination = 'meal plan',
}) async {
  final choices = <Map<String, dynamic>>[
    full,
    ...recipeRows(full['variation_family'] ?? full['related']).where(
      (row) =>
          '${row['id']}' != '${full['id']}' && row['in_household'] != false,
    ),
  ];
  var selected = full;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          choices.length == 1 ? 'Add to $destination?' : 'Choose recipe to add',
        ),
        content: choices.length == 1
            ? Text('${full['title']}')
            : SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final choice in choices)
                        ListTile(
                          title: Text('${choice['title']}'),
                          leading: Icon(
                            '${selected['id']}' == '${choice['id']}'
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          onTap: () => update(() => selected = choice),
                        ),
                    ],
                  ),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

final mealPlanNotices = MealPlanNoticeObserver();

/// Keeps addition notices scoped to their originating screen, including late writes.
class MealPlanNoticeObserver extends NavigatorObserver {
  int epoch = 0;
  Timer? _timer;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _notice;

  void dismiss() {
    epoch++;
    _timer?.cancel();
    _timer = null;
    _notice?.close();
    _notice = null;
  }

  void show(ScaffoldMessengerState messenger, SnackBar notice) {
    dismiss();
    final current = messenger.showSnackBar(notice);
    _notice = current;
    current.closed.then((_) {
      if (identical(_notice, current)) {
        _timer?.cancel();
        _timer = null;
        _notice = null;
      }
    });
    // An action otherwise prevents timeout when accessibility navigation is on.
    _timer = Timer(const Duration(seconds: 5), () {
      current.close();
      if (identical(_notice, current)) _notice = null;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      dismiss();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => dismiss();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      dismiss();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      dismiss();
}
