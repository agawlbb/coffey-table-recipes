import 'package:coffey_table_recipes/src/connection_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    connectedHouseholds.value = {};
  });
  testWidgets(
    'green means an open connection and never flickers for data activity',
    (tester) async {
      connectedHouseholds.value = {'1'};
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ConnectionIndicator(householdId: '1')),
        ),
      );
      expect(find.byTooltip('Connected to server'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.cloud_done)).color,
        Colors.green,
      );
      connectedHouseholds.value = {};
      await tester.pump();
      expect(find.byTooltip('Not connected to server'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsNothing);
    },
  );
}
