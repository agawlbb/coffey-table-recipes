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
      for (final step in (state['recipe'] as Map)['steps'] as List) {
        step['offset_seconds'] = -2280;
      }
      ((state['recipe'] as Map)['steps'] as List).add({
        'id': 'prep:ingredients',
        'instruction': 'Slice potatoes and mince garlic',
        'offset_seconds': -3480,
        'dish_title': 'Preparation',
        'position': 0,
      });
      final first = CookingSessions(
        storage: storage,
        installation: 'a' * 32,
        request: (path, {body}) async => {'session': state},
      );
      await first.accept({
        'sessions': [state],
      });
      await first.planRequest('1', {'session_id': state['id']});
      expect(first.planStart(state), DateTime(2026, 11, 7, 23, 32));
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

  test('late plan replies cannot replace pushed cooking progress', () async {
    final original = planFixture();
    final response = Completer<Map<String, dynamic>>();
    Map<String, dynamic>? sent;
    final service = CookingSessions(
      storage: MemoryLocalStorage(),
      installation: 'a' * 32,
      request: (path, {body}) {
        sent = body;
        return response.future;
      },
    );
    addTearDown(service.dispose);
    await service.accept({
      'sessions': [original],
    });
    final pending = service.planRequest('1', {
      'action': 'feedback',
      'session_id': original['id'],
      'message': 'I am chopping.',
    });
    final newer = {
      ...original,
      'completed': ['1'],
      'dinner_at': (original['dinner_at'] as int) + 3600000,
    };
    await service.accept({
      'sessions': [newer],
    });
    response.complete({
      'session': original,
      'messages': <Map<String, dynamic>>[],
    });
    await pending;
    expect(sent!['current_progress']['completed'], original['completed']);
    expect(service.session('${original['id']}')!['completed'], ['1']);
    expect(
      service.session('${original['id']}')!['dinner_at'],
      newer['dinner_at'],
    );
  });

  test(
    'feedback sends current progress while a cooking save is unanswered',
    () async {
      final state = planFixture();
      final held = Completer<Map<String, dynamic>>();
      Map<String, dynamic>? feedback;
      final service = CookingSessions(
        storage: MemoryLocalStorage(),
        installation: 'a' * 32,
        request: (path, {body}) async {
          if (path.endsWith('/step')) return held.future;
          feedback = body;
          return {'session': state, 'messages': <Map<String, dynamic>>[]};
        },
      );
      addTearDown(service.dispose);
      await service.accept({
        'sessions': [state],
      });
      await service.check('${state['id']}', '1', true);
      await service
          .planRequest('1', {
            'action': 'feedback',
            'session_id': state['id'],
            'message': 'This is taking longer.',
          })
          .timeout(const Duration(seconds: 2));
      expect(feedback!['current_progress']['completed'], ['1']);
      held.complete({'session': state});
    },
  );

  testWidgets(
    'waiting for a device alarm does not hold incoming cooking updates',
    (tester) async {
      final nativeCall = Completer<void>();
      final release = Completer<void>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeTimers.channel,
        (call) async {
          if (call.method == 'schedule') {
            if (!nativeCall.isCompleted) nativeCall.complete();
            await release.future;
          }
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
        request: (path, {body}) async => {},
      );
      addTearDown(service.dispose);
      NativeTimers.active.value = [
        {
          'key': service.startAlarmKey('${state['id']}'),
          'deadline': (state['dinner_at'] as int) - 1000,
        },
      ];
      await service.accept({
        'sessions': [state],
      });
      await tester.pump();
      expect(nativeCall.isCompleted, true);
      final newer = {
        ...state,
        'completed': ['1'],
      };
      await service.accept({
        'sessions': [newer],
      });
      expect(service.session('${state['id']}')!['completed'], ['1']);
      release.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'selector defaults all dishes, remembers dinner setting, and submits selected entries',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

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
      expect(
        tester
            .getBottomRight(find.widgetWithText(FilledButton, 'Create plan'))
            .dy,
        lessThanOrEqualTo(844 - 48),
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
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      expect(
        (tester.getCenter(find.byTooltip('Dinner time')).dy -
                tester.getCenter(find.byType(Switch)).dy)
            .abs(),
        lessThan(4),
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

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
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);

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
        request: (path, {body}) async => path.endsWith('/people')
            ? {
                'people': [
                  {'id': '20', 'display_name': 'Alex'},
                ],
              }
            : {'session': state},
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
      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('End cooking session?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.session('${state['id']}'), isNotNull);
      expect(alarms.length, 1);

      await tester.longPress(find.text('Soup + Bread'));
      await tester.pumpAndSettle();
      expect(find.text('Remove start alarm'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(
        tester.getBottomRight(find.widgetWithText(ListTile, 'Share')).dy,
        lessThanOrEqualTo(844 - 48),
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.widgetWithText(ListTile, 'Alex')).dy,
        lessThanOrEqualTo(844 - 48),
      );
      await tester.tap(find.text('Alex'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Soup + Bread'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove start alarm'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(alarms, isEmpty);
      await tester.longPress(find.text('Soup + Bread'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Set start alarm for '), findsOneWidget);
      await tester.tap(find.textContaining('Set start alarm for '));
      await tester.pumpAndSettle();
      expect(alarms.length, 1);
      await service.removeStartAlarm('${state['id']}');

      unawaited(
        offerStartAlarm(
          tester.element(find.byType(CookingSessionMenu)),
          service,
          state,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Set start alarm for '), findsOneWidget);
      expect(
        find.textContaining(
          formatStartAlarmTime(
            tester.element(find.byType(AlertDialog)),
            service.planStart(state)!,
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Set alarm'));
      await tester.pumpAndSettle();
      final oldDeadline = alarms.values.single['deadline'] as int;
      state['dinner_at'] = (state['dinner_at'] as int) + 3600000;
      await service.accept({
        'sessions': [state],
      });
      await tester.pumpAndSettle();
      expect(alarms.values.single['deadline'], oldDeadline + 3600000);
      state['started_at'] = DateTime.now().millisecondsSinceEpoch;
      await service.accept({
        'sessions': [state],
      });
      await tester.pumpAndSettle();
      expect(alarms, isEmpty);
      expect(service.hasStartAlarm('${state['id']}'), isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
