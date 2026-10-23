import 'package:coffey_table_recipes/src/sync_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'overdue notification reaches the current route and clears after sync',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: syncMessengerKey,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Text('Editing recipe')),
                  ),
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final due = [
        {
          'id': 'save-one',
          'deadline': DateTime.now().millisecondsSinceEpoch - 1,
        },
      ];
      await SyncNotifications.update('web-account', due);
      await tester.pumpAndSettle();
      expect(find.text('Editing recipe'), findsOneWidget);
      expect(find.textContaining('server has not confirmed'), findsOneWidget);
      await SyncNotifications.update('web-account', due);
      await tester.pump();
      expect(find.textContaining('server has not confirmed'), findsOneWidget);
      await SyncNotifications.update('web-account', []);
      await tester.pumpAndSettle();
      expect(find.textContaining('server has not confirmed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'Android receives schedule and cancellation without recipe content',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SyncNotifications.channel, (call) async {
            calls.add(call);
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SyncNotifications.channel, null),
      );
      final changes = [
        {
          'id': 'save-native',
          'deadline': DateTime.now().millisecondsSinceEpoch + 60000,
        },
      ];
      await SyncNotifications.update('native-account', changes);
      await SyncNotifications.update('native-account', []);
      expect(calls.length, 2);
      expect(calls.first.arguments, {
        'scope': 'native-account',
        'changes': changes,
      });
      expect(calls.last.arguments['changes'], isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
