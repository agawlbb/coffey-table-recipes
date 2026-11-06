import 'package:coffey_table_recipes/src/connection_notice.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => offlineStatus.value = false);
  for (final network in ['none', 'wifi']) {
    testWidgets(
      'warning identifies $network availability and explains offline recipe edits',
      (tester) async {
        offlineStatus.value = true;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (_) async => [network],
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => connectionNotice(context, 'edit'),
                  child: const Text('Edit recipe'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Edit recipe'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            network == 'none' ? 'You’re offline.' : 'We can’t reach the server',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('We’ll ask before sending'), findsOneWidget);
      },
    );
  }
}
