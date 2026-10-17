import 'package:coffey_table_recipes/src/cooking_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('coffey_table_recipes/timers'),
          (call) async => call.method == 'list' ? [] : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('coffey_table_recipes/timers'),
          null,
        );
  });
  for (final (description, value, unit, expected)
      in <(String, Object, String, String)>[
        ('padded integer', '350.0000', 'F', '350'),
        ('integer', 350, 'F', '350'),
        ('numeric integer', 350.0, 'F', '350'),
        ('padded fraction', '350.5000', 'F', '350.5'),
        ('meaningful precision', '65.1250', 'C', '65.125'),
        ('converted boiling point', (100 * 9 / 5) + 32, 'F', '212'),
        ('converted oven temperature', '177.7778', 'C', '177.7778'),
        ('negative temperature', '-40.0000', 'C', '-40'),
        ('zero', '0.0000', 'C', '0'),
      ]) {
    testWidgets(
      'cooking formats $description without changing stored temperature',
      (tester) async {
        final action = <String, dynamic>{
          'id': '2',
          'step_id': '1',
          'label': 'Heat griddle',
          'temperature_value': value,
          'temperature_unit': unit,
        };
        await tester.pumpWidget(
          MaterialApp(
            home: CookingMode(
              recipe: {
                'title': 'Temperature test',
                'steps': [
                  {
                    'id': '1',
                    'position': 1,
                    'instruction': 'Heat the griddle.',
                  },
                ],
                'actions': [action],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Heat griddle: $expected\u00b0$unit'), findsOneWidget);
        expect(action['temperature_value'], value);
        expect(action['temperature_unit'], unit);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel timer'));
    await tester.pumpAndSettle();
    expect(find.text('Rest · 0 min 2 sec'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
