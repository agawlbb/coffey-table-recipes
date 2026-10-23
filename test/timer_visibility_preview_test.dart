import 'package:coffey_table_recipes/src/child_mode.dart';

import 'dart:async';

import 'package:coffey_table_recipes/src/active_timers.dart';
import 'package:coffey_table_recipes/src/native_timers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    childMode.value = false;
    NativeTimers.active.value = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTimers.channel, null);
  });

  testWidgets(
    'timers remain visible across pages and stop safely from the global sheet',
    (tester) async {
      final rows = <Map<String, dynamic>>[];
      var failCancel = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeTimers.channel, (call) async {
            if (call.method == 'list') return rows;
            final args = call.arguments as Map;
            if (call.method == 'schedule') {
              rows.add(Map<String, dynamic>.from(args));
            }
            if (call.method == 'cancel') {
              if (failCancel) throw PlatformException(code: 'cancel');
              rows.removeWhere((row) => row['key'] == args['key']);
            }
            return null;
          });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => ChildModeScope(
            child: Overlay.wrap(
              child: ActiveTimerHost(navigatorKey: navigator, child: child!),
            ),
          ),
          home: const Scaffold(body: Text('Recipe page')),
        ),
      );
      await tester.pump();
      await NativeTimers.schedule(
        '14:1',
        DateTime.now().add(const Duration(minutes: 3)),
        'Orange chicken',
      );
      await tester.pump();
      expect(find.text('Orange chicken'), findsOneWidget);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Another page'), findsOneWidget);
      expect(find.text('Orange chicken'), findsOneWidget);
      await tester.tap(find.text('Orange chicken'));
      await tester.pumpAndSettle();
      childMode.value = true;
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Stop'))
            .onPressed,
        isNull,
      );
      childMode.value = false;
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not stop'), findsOneWidget);
      expect(NativeTimers.active.value, hasLength(1));
      failCancel = false;
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('No running timers'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Another page'), findsOneWidget);
      expect(find.text('Orange chicken'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('an older restore cannot erase a newly scheduled timer', (
    tester,
  ) async {
    final pending = Completer<List<dynamic>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeTimers.channel,
          (call) async => call.method == 'list' ? pending.future : null,
        );
    final restore = NativeTimers.restore();
    await tester.pump();
    await NativeTimers.schedule(
      '1:2',
      DateTime.now().add(const Duration(minutes: 1)),
      'Soup',
    );
    pending.complete([]);
    await restore;
    expect(NativeTimers.active.value.single['title'], 'Soup');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'selecting a tone previews for one second and selector close stops without saving',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeTimers.channel, (call) async {
            calls.add(call);
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const AlarmTonePicker(
                    selected: '',
                    tones: [
                      {'value': '', 'label': 'Default alarm'},
                      {'value': 'bright.wav', 'label': 'Bright bell'},
                    ],
                  ),
                ),
                child: const Text('Choose'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_circle_outline), findsNothing);
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
      await tester.tap(find.text('Bright bell'));
      await tester.pump();
      expect(calls.last.method, 'previewTone');
      expect(calls.last.arguments, {'tone': 'bright.wav'});
      await tester.tap(find.text('Default alarm'));
      await tester.pump();
      expect(calls.last.arguments, {'tone': ''});
      expect(calls[calls.length - 2].method, 'stopPreview');
      await tester.pump(const Duration(milliseconds: 999));
      expect(calls.last.method, 'previewTone');
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls.last.method, 'stopPreview');
      await tester.tap(find.text('Bright bell'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'stopPreview');
      expect(calls.where((call) => call.method == 'setTone'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
