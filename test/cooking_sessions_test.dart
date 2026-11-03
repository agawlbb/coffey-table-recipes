import 'package:coffey_table_recipes/src/api.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:coffey_table_recipes/src/cooking_mode.dart';
import 'package:coffey_table_recipes/src/cooking_session_ui.dart';
import 'package:coffey_table_recipes/src/cooking_sessions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'timer_sync_test.dart' show cookingFixture;

class _WakeRecorder extends WakelockPlusMacOSPlugin {
  bool requested = false;
  @override
  Future<void> toggle({required bool enable}) async {
    requested = enable;
  }
}

void main() {
  testWidgets(
    'menu has only recipe and Open or Join; long press directly shares with a member',
    (tester) async {
      final writes = <String>[];
      final state = cookingFixture(joined: []);
      final joined = cookingFixture(id: '22222222222222222222222222222222');
      (joined['recipe'] as Map)['title'] = 'Bread';
      final service = CookingSessions(
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        request: (path, {body}) async {
          if (body == null && path.endsWith('/people')) {
            return {
              'people': [
                {'id': '10', 'display_name': 'Alex'},
              ],
            };
          }
          writes.add(path);
          return {'session': state};
        },
      );
      addTearDown(service.dispose);
      await service.accept({
        'sessions': [state, joined],
      });
      Widget menu(BuildContext context) => Drawer(
        child: CookingSessionMenu(menuBuilder: menu, sessions: service),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(),
            drawer: Builder(builder: menu),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      expect(find.textContaining('completed'), findsNothing);
      await tester.longPress(find.text('Soup'));
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Share with'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
      await tester.tap(find.text('Alex'));
      await tester.pumpAndSettle();
      expect(writes.single, endsWith('/share'));
      expect(find.text('Alex'), findsNothing);
    },
  );
  testWidgets(
    'menu joins, switches dishes and reopens without losing foreground presence',
    (tester) async {
      final previousWake = wakelockPlusPlatformInstance;
      final wake = _WakeRecorder();
      wakelockPlusPlatformInstance = wake;
      addTearDown(() => wakelockPlusPlatformInstance = previousWake);

      final soup = cookingFixture(joined: []);
      final bread = cookingFixture(id: '22222222222222222222222222222222');
      (bread['recipe'] as Map)['title'] = 'Bread';
      final states = {'${soup['id']}': soup, '${bread['id']}': bread};
      late CookingSessions service;
      service = CookingSessions(
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        request: (path, {body}) async {
          final id = path.split('/')[3];
          final state = states[id]!;
          if (path.endsWith('/join')) {
            state['joined_devices'] = [service.installation];
          }
          state['revision'] = (state['revision'] as int) + 1;
          return {'session': state};
        },
      );
      addTearDown(service.dispose);
      await service.accept({'sessions': states.values.toList()});
      Widget menu(BuildContext context) => Drawer(
        child: CookingSessionMenu(menuBuilder: menu, sessions: service),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [cookingRouteObserver],
          home: Scaffold(
            appBar: AppBar(),
            drawer: Builder(builder: menu),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Soup'));
      await tester.pumpAndSettle();
      expect(find.byType(CookingMode), findsOneWidget);
      expect(service.joined(service.session('${soup['id']}')!), isTrue);
      expect(service.visibleSession, soup['id']);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bread').last);
      await tester.pumpAndSettle();
      expect(service.visibleSession, bread['id']);
      expect(wake.requested, isTrue);
      expect(service.sessions, hasLength(2));
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bread').last);
      await tester.pumpAndSettle();
      expect(service.visibleSession, bread['id']);
      expect(wake.requested, isTrue);
      expect(find.byType(CookingMode), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'joined cooking opens at first unchecked step and remote updates preserve scroll',
    (tester) async {
      final state = cookingFixture();
      (state['recipe'] as Map)['steps'] = [
        for (var i = 1; i <= 12; i++)
          {
            'id': '$i',
            'position': i,
            'instruction': 'Instruction $i. ${'Stir slowly. ' * 12}',
          },
      ];
      state['completed'] = [for (var i = 1; i < 9; i++) '$i'];
      final service = CookingSessions(
        request: (path, {body}) async => {'session': state},
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      addTearDown(service.dispose);
      await service.accept({
        'sessions': [state],
      });
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [cookingRouteObserver],
          home: CookingMode(
            recipe: Map<String, dynamic>.from(state['recipe'] as Map),
            sessionId: '${state['id']}',
            sessions: service,
            menuBuilder: (_) => const Drawer(child: Text('Cooking sessions')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Step 9').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final offset = scroll.pixels;
      await service.accept({
        'sessions': [
          {
            ...state,
            'revision': 2,
            'completed': [...state['completed'] as List, '9'],
          },
        ],
      });
      await tester.pump();
      expect(scroll.pixels, offset);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('Cooking sessions'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'notification Stop clears expired cooking control and stale snapshots cannot restore it',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final state = cookingFixture();
      final deadline = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch;
      state['timers'] = [
        {
          'action_id': '2',
          'deadline_ms': deadline,
          'cancelled': false,
          'extension_seconds': 120,
          'revision': 1,
        },
      ];
      final service = CookingSessions(
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        request: (path, {body}) async {
          throw ApiException(503, 'Offline');
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
      expect(find.textContaining('Time is up'), findsOneWidget);
      await service.importNativeActions([
        {
          'account_uid': null,
          'installation_id': service.installation,
          'session_id': state['id'],
          'operation_id': 'ffffffffffffffffffffffffffffffff',
          'body': {
            'action_id': '2',
            'cancelled': true,
            'revision': 1,
            'extension_seconds': 0,
            'expected_deadline_ms': deadline,
          },
        },
      ]);
      await tester.pump();
      expect(find.textContaining('Time is up'), findsNothing);
      expect(find.text('Simmer · 1 min'), findsOneWidget);
      await service.accept({
        'sessions': [state],
      });
      await tester.pump();
      expect(find.textContaining('Time is up'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'ending with running timers asks once before cancelling everywhere',
    (tester) async {
      final state = cookingFixture();
      state['timers'] = [
        {
          'action_id': '2',
          'deadline_ms': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'cancelled': false,
        },
      ];
      var ended = 0;
      final service = CookingSessions(
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        request: (path, {body}) async {
          if (path.endsWith('/end')) {
            ended++;
            state['ended_at'] = 1800000000001;
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
      await tester.ensureVisible(find.text('End cooking session'));
      await tester.tap(find.text('End cooking session'));
      await tester.pumpAndSettle();
      expect(ended, 0);
      await tester.tap(find.text('Keep cooking'));
      await tester.pumpAndSettle();
      expect(ended, 0);
      await tester.tap(find.text('End cooking session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();
      expect(ended, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
