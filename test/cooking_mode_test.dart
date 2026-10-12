import 'package:coffey_table_recipes/src/cooking_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cooking tracks progress, opens ingredients and runs a timer', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: CookingMode(
          now: () => now,
          recipe: {
            'title': 'Test supper',
            'ingredients': [
              {'group_id': null, 'original_text': '250 g flour'},
            ],
            'steps': [
              {'id': '1', 'position': 1, 'instruction': 'Mix and rest.'},
            ],
            'actions': [
              {
                'id': '2',
                'step_id': '1',
                'duration_seconds': 2,
                'label': 'Rest',
              },
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.text('1 of 1 steps completed'), findsOneWidget);
    await tester.tap(find.text('View ingredients'));
    await tester.pumpAndSettle();
    expect(find.text('• 250 g flour'), findsOneWidget);
    await tester.tap(find.text('Back to cooking'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Rest · 0 min 2 sec'), 200);
    await tester.tap(find.text('Rest · 0 min 2 sec'));
    await tester.pump();
    expect(find.textContaining('Cancel'), findsOneWidget);
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Time is up'), findsOneWidget);
    await tester.tap(find.textContaining('Cancel'));
    await tester.pump();
    expect(find.text('Rest · 0 min 2 sec'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
