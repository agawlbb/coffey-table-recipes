import 'dart:async';

import 'package:coffey_table_recipes/src/combined_cooking.dart';
import 'package:coffey_table_recipes/src/cooking_mode.dart';
import 'package:coffey_table_recipes/src/cooking_session_ui.dart';
import 'package:coffey_table_recipes/src/cooking_sessions.dart';
import 'package:coffey_table_recipes/src/native_timers.dart';
import 'package:coffey_table_recipes/src/shopping_socket.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'support/local_storage.dart';
import 'timer_sync_test.dart' show cookingFixture;

Map<String, dynamic> planFixture() {
  final s = cookingFixture();
  s['combined'] = true;
  s['started_at'] = null;
  s['dinner_at'] = DateTime.now()
      .add(const Duration(hours: 8))
      .millisecondsSinceEpoch;
  s['plan_revision'] = 1;
  final recipe = s['recipe'] as Map;
  recipe['title'] = 'Soup + Bread';
  for (final step in recipe['steps'] as List) {
    step['offset_seconds'] = -3600;
    step['dish_title'] = 'Soup';
    step['source_order'] = 0;
  }
  return s;
}

class _Wake extends WakelockPlusMacOSPlugin {
  @override
  Future<void> toggle({required bool enable}) async {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    NativeTimers.active.value = [];
    final previous = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = _Wake();
    addTearDown(() => wakelockPlusPlatformInstance = previous);
  });

  test('planning and session actions use authenticated socket routes', () {
    expect(isAiPath('/households/1/cooking-plan'), isTrue);
    expect(isVpsDataPath('/me/cooking-sessions/${'a' * 32}/start'), isTrue);
    expect(isVpsDataPath('/me/cooking-sessions/${'a' * 32}/dinner'), isTrue);
  });

  test(
    'saved plan reopens offline and start time crosses midnight correctly',
    () async {
      final storage = MemoryLocalStorage();
      final state = planFixture();
      state['dinner_at'] = DateTime(2026, 11, 8, 0, 30).millisecondsSinceEpoch;
      final first = CookingSessions(
        storage: storage,
        installation: 'a' * 32,
        request: (path, {body}) async => {'session': state},
      );
      await first.planRequest('1', {'session_id': state['id']});
      expect(first.planStart(state), DateTime(2026, 11, 7, 23, 30));
      first.dispose();
      final reopened = CookingSessions(
        storage: storage,
        installation: 'a' * 32,
        request: (path, {body}) async => throw StateError('Offline'),
      );
      addTearDown(reopened.dispose);
      await reopened.start();
      expect(reopened.session('${state['id']}')!['recipe'], state['recipe']);
      expect(
        reopened.session('${state['id']}')!['dinner_at'],
        state['dinner_at'],
      );
    },
  );

  testWidgets(
    'selector defaults all dishes, remembers dinner setting, and submits selected entries',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final pending = Completer<Map<String, dynamic>>();
      final service = CookingSessions(
        storage: MemoryLocalStorage(),
        installation: 'a' * 32,
        request: (path, {body}) async {
          calls.add(body!);
          return pending.future;
        },
      );
      addTearDown(service.dispose);
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                page = context;
                return const DinnerTimeSetting();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dinner time'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '7');
      await tester.enterText(fields.at(1), '15');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect((await DinnerTimeSetting.load()).minute, 15);
      await tester.pumpWidget(
        MaterialApp(
          home: CookingSessionsScope(
            sessions: service,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  page = context;
                  return TextButton(
                    onPressed: () =>
                        showCombinedCooking(context, '1', '2026-11-07', [
                          {
                            'id': 'soup',
                            'kind': 'recipe',
                            'title': 'Soup',
                            'available': true,
                          },
                          {
                            'id': 'bread',
                            'kind': 'recipe',
                            'title': 'Bread',
                            'available': true,
                          },
                        ]),
                    child: const Text('Cook together'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Cook together'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((w) => w.value == true),
        isTrue,
      );
      await tester.tap(find.text('Bread'));
      await tester.tap(find.text('Create plan'));
      await tester.pump();
      expect(calls.single['entry_ids'], ['soup']);
      expect(
        DateTime.fromMillisecondsSinceEpoch(calls.single['dinner_at'] as int)
            .minute,
        15,
      );
      // Close the host while the request is pending; a late reply must not navigate.
      expect(page.mounted, isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.completeError(StateError('fixture disconnected'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'saved combined session renders timeline and feedback uses current session',
    (tester) async {
      var state = planFixture();
      final calls = <Map<String, dynamic>>[];
      final service = CookingSessions(
        storage: MemoryLocalStorage(),
        installation: 'a' * 32,
        request: (path, {body}) async {
          if (path.endsWith('/cooking-plan')) {
            calls.add(body!);
            return {
              'session': state,
              'messages': [
                if (body['action'] == 'feedback')
                  {
                    'role': 'assistant',
                    'content': 'Allow extra chopping time.',
                  },
              ],
            };
          }
          return {'session': state};
        },
      );
      addTearDown(service.dispose);
      await service.accept({
        'sessions': [state],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CookingMode(
            recipe: Map<String, dynamic>.from(state['recipe'] as Map),
            sessionId: '${state['id']}',
            sessions: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start cooking'), findsOneWidget);
      expect(find.textContaining('· Soup'), findsWidgets);
      final feedback = find.text('Provide feedback');
      await tester.ensureVisible(feedback);
      await tester.tap(feedback);
      await tester.pumpAndSettle();
      expect(calls.single['action'], 'history');
      state = {
        ...state,
        'completed': ['1'],
        'started_at': DateTime.now().millisecondsSinceEpoch,
      };
      await service.accept({
        'sessions': [state],
      });
      await tester.enterText(find.byType(TextField), 'I chop slowly');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(calls.last['message'], 'I chop slowly');
      expect(calls.last['action'], 'feedback');
      expect(find.text('Allow extra chopping time.'), findsOneWidget);
      expect(service.session('${state['id']}')!['completed'], ['1']);
    },
  );

  testWidgets(
    'device start alarms persist, shift without AI, show in menu and cancel on starting',
    (tester) async {
      final alarms = <String, Map<String, dynamic>>{};
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeTimers.channel,
        (call) async {
          final args = call.arguments as Map? ?? {};
          if (call.method == 'schedule') {
            alarms['${args['key']}'] = Map<String, dynamic>.from(args);
          }
          if (call.method == 'cancel') alarms.remove(args['key']);
          if (call.method == 'list') return alarms.values.toList();
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeTimers.channel,
          null,
        ),
      );
      final state = planFixture();
      final service = CookingSessions(
        storage: MemoryLocalStorage(),
        installation: 'a' * 32,
        request: (path, {body}) async => {'session': state},
      );
      addTearDown(service.dispose);
      await service.accept({
        'sessions': [state],
      });
      await service.setStartAlarm('${state['id']}');
      expect(alarms.length, 1);
      NativeTimers.active.value = [];
      await NativeTimers.restore();
      expect(service.hasStartAlarm('${state['id']}'), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CookingSessionMenu(
              sessions: service,
              menuBuilder: (_) => const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.alarm), findsOneWidget);
      await tester.longPress(find.text('Soup + Bread'));
      await tester.pumpAndSettle();
      expect(find.text('Remove start alarm'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      await tester.tap(find.text('Remove start alarm'));
      await tester.pumpAndSettle();
      expect(alarms, isEmpty);
      await service.setStartAlarm('${state['id']}');
      final oldDeadline = alarms.values.single['deadline'] as int;
      state['dinner_at'] = (state['dinner_at'] as int) + 3600000;
      await service.accept({
        'sessions': [state],
      });
      expect(alarms.values.single['deadline'], oldDeadline + 3600000);
      state['started_at'] = DateTime.now().millisecondsSinceEpoch;
      await service.accept({
        'sessions': [state],
      });
      expect(alarms, isEmpty);
      expect(service.hasStartAlarm('${state['id']}'), isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
