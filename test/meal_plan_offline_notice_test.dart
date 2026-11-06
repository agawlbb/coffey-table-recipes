import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/connection_notice.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';

void main() {
  testWidgets('offline warning cancels, then holds until a healthy reconnect', (
    tester,
  ) async {
    offlineStatus.value = false;
    offlineStatus.value = true;
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                if (await allowMealPlanChange(context)) changes++;
              },
              child: const Text('Change meal'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Change meal'));
    await tester.pumpAndSettle();
    expect(find.text('You’re offline'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes, 0);
    await tester.tap(find.text('Change meal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue offline'));
    await tester.pumpAndSettle();
    expect(changes, 1);
    await tester.tap(find.text('Change meal'));
    await tester.pumpAndSettle();
    expect(changes, 2);
    expect(find.text('You’re offline'), findsNothing);
    offlineStatus.value = false;
    await tester.tap(find.text('Change meal'));
    await tester.pumpAndSettle();
    expect(changes, 3);
    offlineStatus.value = true;
    await tester.tap(find.text('Change meal'));
    await tester.pumpAndSettle();
    expect(find.text('You’re offline'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    offlineStatus.value = false;
  });
}
