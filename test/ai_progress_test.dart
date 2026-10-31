import 'dart:async';

import 'package:coffey_table_recipes/src/ai_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'progress is announced only during its own AI run and clears on failure',
    (tester) async {
      final progress = AiRunProgress();
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AiProgressText(progress))),
      );
      final pending = Completer<void>();
      final result = progress.run(() {
        (Zone.current[aiProgressZoneKey] as void Function(String, int))(
          'Reading source…',
          4,
        );
        return pending.future;
      });
      await tester.pump();
      expect(find.text('Reading source… (4 s)'), findsOneWidget);
      pending.complete();
      await result;
      await tester.pump();
      expect(find.text('Reading source… (4 s)'), findsNothing);
      await expectLater(
        progress.run<void>(() async {
          throw StateError('failed');
        }),
        throwsStateError,
      );
      expect(progress.value, isNull);
    },
  );

  test(
    'late updates cannot change a disposed or another screen progress',
    () async {
      final first = AiRunProgress();
      final second = AiRunProgress();
      addTearDown(second.dispose);
      late void Function(String, int) update;
      await first.run(() async {
        update = Zone.current[aiProgressZoneKey] as void Function(String, int);
      });
      first.dispose();
      update('Late event', 10);
      expect(second.value, isNull);
    },
  );
}
