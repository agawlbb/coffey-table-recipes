import 'child_mode.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'recipe_browser.dart';
import 'recipe_editor.dart';
import 'shopping_item_id.dart';

String mealPlanDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

Future<void> addDatedMeal(
  BuildContext context, {
  required String householdId,
  required Map<String, dynamic> recipe,
  required RecipeRequest request,
  required RecipeSave save,
  VoidCallback? viewPlan,
  bool exactRecipe = false,
}) async {
  if (childMode.value) return;
  final startingEpoch = mealPlanNotices.epoch;
  try {
    final path = '/households/$householdId/meal-plan';
    final localDate = mealPlanDate(DateTime.now());
    var state = await request('$path?from=$localDate&to=$localDate');
    if (!context.mounted || startingEpoch != mealPlanNotices.epoch) return;
    final today = DateTime.tryParse('${state['today']}') ?? DateTime.now();
    var full = recipe;
    if (!exactRecipe &&
        !full.containsKey('variation_family') &&
        !full.containsKey('related')) {
      final response = await request(
        '/households/$householdId/recipes/${recipe['id']}',
      );
      full = Map<String, dynamic>.from(response['recipe'] as Map);
    }
    if (!context.mounted || startingEpoch != mealPlanNotices.epoch) return;
    final selected = exactRecipe
        ? await selectMealDate(
            context,
            today,
          ).then((date) => date == null ? null : {...full, '_meal_date': date})
        : await chooseDatedMealRecipe(context, full, today: today);
    if (selected == null || !context.mounted) return;
    final date = selected['_meal_date'] as String;
    final past = date.compareTo(mealPlanDate(today)) < 0;
    if (past && !await confirmPastMealChange(context)) return;
    if (!context.mounted) return;
    final noticeEpoch = mealPlanNotices.epoch;
    state = await request('$path?from=$date&to=$date');
    if (!context.mounted || noticeEpoch != mealPlanNotices.epoch) return;
    await save(path, {
      'revision': state['revision'],
      'operation': 'add',
      'id': newShoppingItemId(),
      'kind': 'recipe',
      'recipe_id': '${selected['id']}',
      'date': date,
      'confirm_past': past,
    });
    if (!context.mounted || noticeEpoch != mealPlanNotices.epoch) return;
    final active = await addMealPairings(
      context,
      householdId: householdId,
      recipeId: '${selected['id']}',
      date: date,
      request: request,
      save: save,
      past: past,
    );
    if (!active ||
        !context.mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
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
  String actionLabel = 'Add',
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
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> chooseDatedMealRecipe(
  BuildContext context,
  Map<String, dynamic> full, {
  required DateTime today,
}) async {
  var selected = full;
  final variants = recipeRows(full['variation_family'] ?? full['related'])
      .where(
        (row) =>
            '${row['id']}' != '${full['id']}' && row['in_household'] != false,
      );
  if (variants.isNotEmpty) {
    final choice = await confirmMealRecipe(context, full, actionLabel: 'Next');
    if (choice == null || !context.mounted) return null;
    selected = choice;
  }
  final date = await selectMealDate(context, today);
  return date == null ? null : {...selected, '_meal_date': date};
}

Future<String?> selectMealDate(BuildContext context, DateTime today) async {
  final first = DateTime(today.year, today.month, today.day);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add to meal plan'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var offset = 0; offset < 7; offset++)
                Builder(
                  builder: (context) {
                    final date = DateTime(
                      first.year,
                      first.month,
                      first.day + offset,
                    );
                    return ListTile(
                      key: ValueKey('choose-meal-${mealPlanDate(date)}'),
                      title: Text(
                        MaterialLocalizations.of(context).formatFullDate(date),
                      ),
                      onTap: () => Navigator.pop(context, mealPlanDate(date)),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Another date…'),
                onTap: () => Navigator.pop(context, 'calendar'),
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
      ],
    ),
  );
  if (result != 'calendar' || !context.mounted) return result;
  final date = await showDatePicker(
    context: context,
    initialDate: first,
    firstDate: DateTime(2000),
    lastDate: DateTime(2199, 12, 31),
  );
  return date == null ? null : mealPlanDate(date);
}

Future<bool> confirmPastMealChange(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change this past meal?'),
        content: const Text('This will update your cooking history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change'),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> addMealPairings(
  BuildContext context, {
  required String householdId,
  required String recipeId,
  required String date,
  required RecipeRequest request,
  required RecipeSave save,
  required bool past,
}) async {
  final path = '/households/$householdId/meal-plan';
  final epoch = mealPlanNotices.epoch;
  try {
    final state = await request('$path?from=$date&to=$date');
    final paired = await request('$path/pairings/$recipeId');
    if (!context.mounted || epoch != mealPlanNotices.epoch) return false;
    final existing =
        recipeRows(state['entries'])
            .where((row) => row['plan_date'] == date)
            .map((row) => '${row['recipe_id']}')
            .toSet()
          ..add(recipeId);
    final suggestions = recipeRows(paired['recipes'])
        .where((row) => !existing.contains('${row['id']}'))
        .toList();
    if (suggestions.isEmpty) return true;
    final selected = <String>{};
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Frequently made together'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final recipe in suggestions)
                    CheckboxListTile(
                      title: Text('${recipe['title']}'),
                      value: selected.contains('${recipe['id']}'),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected.add('${recipe['id']}');
                        } else {
                          selected.remove('${recipe['id']}');
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Add selected'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    if (add != true) return true;
    if (past && !await confirmPastMealChange(context)) return true;
    if (!context.mounted) return false;
    final saveEpoch = mealPlanNotices.epoch;
    for (final id in selected) {
      final current = await request('$path?from=$date&to=$date');
      if (!context.mounted || saveEpoch != mealPlanNotices.epoch) return false;
      await save(path, {
        'revision': current['revision'],
        'operation': 'add',
        'id': newShoppingItemId(),
        'kind': 'recipe',
        'recipe_id': id,
        'date': date,
        'confirm_past': past,
      });
    }
    return context.mounted && saveEpoch == mealPlanNotices.epoch;
  } catch (_) {
    if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add paired dishes. Your meal was added.'),
        ),
      );
    }
    return context.mounted && epoch == mealPlanNotices.epoch;
  }
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
