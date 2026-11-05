import 'package:coffey_table_recipes/src/connection_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    connectedHouseholds.value = {};
    pendingSyncMessage.value = null;
  });

  testWidgets(
    'connected household stays amber until pending saves are confirmed',
    (tester) async {
      connectedHouseholds.value = {'1'};
      pendingSyncMessage.value = '1 change(s) waiting to sync';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ConnectionIndicator(householdId: '1')),
        ),
      );
      expect(find.byIcon(Icons.cloud_done), findsNothing);
      expect(find.byTooltip('1 change(s) waiting to sync'), findsOneWidget);
      connectedHouseholds.value = {};
      await tester.pump();
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      connectedHouseholds.value = {'1'};
      pendingSyncMessage.value = 'Sync paused';
      await tester.pump();
      expect(find.byIcon(Icons.cloud_done), findsNothing);
      pendingSyncMessage.value = null;
      await tester.pump();
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      expect(find.byTooltip('All changes synced'), findsOneWidget);
      connectedHouseholds.value = {};
      await tester.pump();
      expect(find.byIcon(Icons.cloud_done), findsNothing);
    },
  );
}
