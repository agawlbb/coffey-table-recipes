import 'package:coffey_table_recipes/src/meal_plan_dish_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets('wraps at word boundaries with text scale $scale', (
      tester,
    ) async {
      const title = 'Grilled Hamburgers with caramelized onions';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Center(
                child: SizedBox(
                  width: 110,
                  child: MealPlanDishTitle(title: title),
                ),
              ),
            ),
          ),
        ),
      );
      final caption = tester.widget<Text>(
        find.descendant(
          of: find.byType(MealPlanDishTitle),
          matching: find.byType(Text),
        ),
      );
      final words = caption.data!.replaceAll('…', '').split(RegExp(r'\s+'));
      expect(
        words.where((word) => word.isNotEmpty).every(title.split(' ').contains),
        isTrue,
      );
      expect(caption.softWrap, isFalse);
      expect(caption.data!.split('\n').length, lessThanOrEqualTo(2));
      expect(find.byTooltip(title), findsOneWidget);
      expect(find.bySemanticsLabel(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('short dish name stays on one line', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 160,
            child: MealPlanDishTitle(title: 'Baked Beans'),
          ),
        ),
      ),
    );
    expect(find.text('Baked Beans'), findsOneWidget);
    expect(tester.getSize(find.text('Baked Beans')).height, lessThan(30));
  });
}
