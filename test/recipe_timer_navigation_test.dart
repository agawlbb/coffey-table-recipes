import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/cooking_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'recipe timer explains cooking mode and opens it only on confirmation',
    (tester) async {
      const channel = MethodChannel('coffey_table_recipes/timers');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'list' ? [] : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '2',
            recipeId: '1',
            title: 'Soup',
            request: (_) async => {
              'recipe': {
                'id': '1',
                'title': 'Soup',
                'steps': [
                  {
                    'id': 's',
                    'position': 1,
                    'instruction': 'Simmer for one minute.',
                  },
                ],
                'actions': [
                  {
                    'id': 'a',
                    'step_id': 's',
                    'action_type': 'timer',
                    'label': 'Simmer',
                    'duration_seconds': 60,
                  },
                  {
                    'id': 'b',
                    'step_id': 's',
                    'action_type': 'appliance_temperature',
                    'label': 'Oven',
                    'temperature_value': 180,
                    'temperature_unit': 'C',
                  },
                ],
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final timer = find.widgetWithText(InputChip, 'Simmer · 1 min');
      await tester.ensureVisible(timer);
      await tester.tap(timer);
      await tester.pumpAndSettle();
      expect(find.text('Open in cooking mode to use timers.'), findsOneWidget);
      expect(find.byType(CookingMode), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CookingMode), findsNothing);
      expect(
        tester
            .widget<InputChip>(find.widgetWithText(InputChip, 'Oven · 180°C'))
            .onPressed,
        isNull,
      );
      await tester.tap(timer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open cooking mode'));
      await tester.pumpAndSettle();
      expect(find.byType(CookingMode), findsOneWidget);
      expect(calls, isNot(contains('schedule')));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
