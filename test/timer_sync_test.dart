import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/cooking_sessions.dart';
import 'package:coffey_table_recipes/src/native_timers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Map<String, dynamic> cookingFixture({
  String id = '11111111111111111111111111111111',
  List<String> joined = const ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
}) => {
  'id': id,
  'revision': 1,
  'ended_at': null,
  'created_at': 1800000000000,
  'household_id': '1',
  'recipe': {
    'id': '1',
    'title': 'Soup',
    'steps': [
      {'id': '1', 'position': 1, 'instruction': 'Simmer'},
    ],
    'actions': [
      {'id': '2', 'step_id': '1', 'label': 'Simmer', 'duration_seconds': 60},
    ],
  },
  'completed': <String>[],
  'step_revisions': <String, dynamic>{},
  'timers': <Map<String, dynamic>>[],
  'joined_devices': joined,
  'open_elsewhere': true,
  'invited': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CookingSessions sync;
  late Map<String, dynamic> state;
  late List<Map<String, dynamic>> writes;
  late bool offline;
  late Set<String> operations;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (offline) throw ApiException(503, 'Offline');
    if (body == null) {
      return {
        'sessions': [state],
      };
    }
    writes.add(Map<String, dynamic>.from(body));
    final action = path.split('/').last;
    if (operations.add(body['operation_id'] as String)) {
      if (action == 'timer') {
        final timers = state['timers'] as List;
        final old = timers.isEmpty ? null : timers.first;
        state['timers'] = [
          {
            'timer_id': 'session:${state['id']}:2',
            'session_id': state['id'],
            'action_id': '2',
            'source_device': 'session',
            'title': 'Soup · Simmer',
            'deadline_ms': body['deadline_ms'] ?? old?['deadline_ms'],
            'cancelled': body['cancelled'],
            'extension_seconds': body['extension_seconds'] ?? 0,
            'revision': (old?['revision'] ?? 0) + 1,
          },
        ];
      } else if (action == 'step') {
        state['completed'] = body['checked'] == true ? ['1'] : [];
        state['step_revisions'] = {'1': 1};
      } else if (action == 'join') {
        state['joined_devices'] = [sync.installation];
      } else if (action == 'end') {
        state['ended_at'] = 1800000000001;
      }
      state['revision'] = (state['revision'] as int) + 1;
    }
    return {'session': jsonDecode(jsonEncode(state))};
  }

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeTimers.channel,
          (call) async => call.method == 'list' ? [] : null,
        );
    state = cookingFixture();
    writes = [];
    operations = {};
    offline = false;
    sync = CookingSessions(
      request: request,
      installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await sync.start();
    await sync.accept({
      'sessions': [state],
    });
  });
  test(
    'device registration is serialized across concurrent refreshes',
    () async {
      final first = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final service = CookingSessions(
        registerDevice: () async {
          calls++;
          if (calls == 1) {
            first.complete();
            await release.future;
          }
        },
      );
      final one = service.refreshDeviceRegistration();
      await first.future;
      final two = service.refreshDeviceRegistration();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      release.complete();
      await Future.wait([one, two]);
      expect(calls, 2);
      service.dispose();
    },
  );

  tearDown(() {
    sync.dispose();
    NativeTimers.active.value = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTimers.channel, null);
  });
  test(
    'failed device registration does not skip initial session refresh',
    () async {
      final accounts = StreamController<String?>();
      final refreshed = Completer<void>();
      final service = CookingSessions(
        accountChanges: accounts.stream,
        registerDevice: () async => throw ApiException(503, 'Disconnected'),
        request: (path, {body}) async {
          if (!refreshed.isCompleted) refreshed.complete();
          return {
            'sessions': [state],
          };
        },
      );
      await service.start();
      accounts.add('test-user');
      await refreshed.future;
      await Future<void>.delayed(Duration.zero);
      expect(service.sessions.single['id'], state['id']);
      expect(service.error, isNull);
      service.dispose();
      await accounts.close();
    },
  );

  test('background disconnect stays silent and refresh recovers', () async {
    offline = true;
    await sync.refresh();
    expect(sync.error, isNull);
    offline = false;
    await sync.refresh();
    expect(sync.sessions.single['id'], state['id']);
  });

  test('declined session remains available to join and joined sessions stop prompting', () async {
    state = cookingFixture(joined: []);
    await sync.accept({
      'sessions': [state],
    });
    expect(sync.invitations, hasLength(1));
    sync.offered.add('${state['id']}');
    expect(sync.invitations, isEmpty);
    expect(sync.sessions, hasLength(1));
    await sync.join('${state['id']}');
    expect(sync.joined(sync.sessions.single), isTrue);
    expect(sync.invitations, isEmpty);
  });
  test('checking and unchecking updates cooking progress', () async {
    await sync.check('${state['id']}', '1', true);
    expect(sync.sessions.single['completed'], ['1']);
    await sync.check('${state['id']}', '1', false);
    expect(sync.sessions.single['completed'], isEmpty);
  });
  test(
    'offline start and cancellation survive restart with the original deadline',
    () async {
      offline = true;
      final deadline = DateTime.now().add(const Duration(minutes: 12));
      final key = 'remote:session:${state['id']}:2';
      await NativeTimers.schedule(key, deadline, 'Soup');
      await sync.refresh();
      await NativeTimers.cancel(key);
      await sync.refresh();
      final raw = await SharedPreferencesAsync().getString(
        'cooking_outbox_null',
      );
      expect((jsonDecode(raw!) as List), hasLength(2));
      sync.dispose();
      sync = CookingSessions(
        request: request,
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await sync.start();
      offline = false;
      await sync.refresh();
      expect(writes, hasLength(2));
      expect(writes.first['deadline_ms'], deadline.millisecondsSinceEpoch);
      expect(state['timers'][0]['cancelled'], true);
      expect(
        jsonDecode(
          (await SharedPreferencesAsync().getString('cooking_outbox_null'))!,
        ),
        isEmpty,
      );
    },
  );
  test('lost timer response does not create a duplicate timer', () async {
    sync.dispose();
    var lose = true;
    sync = CookingSessions(
      installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      request: (path, {body}) async {
        final result = await request(path, body: body);
        if (body != null && path.endsWith('/timer') && lose) {
          lose = false;
          throw ApiException(503, 'Response lost');
        }
        return result;
      },
    );
    await sync.start();
    await sync.accept({
      'sessions': [state],
    });
    await sync.timerChanged(
      'remote:session:${state['id']}:2',
      DateTime.now().add(const Duration(minutes: 2)),
      'Soup',
    );
    await sync.refresh();
    expect(writes.length, greaterThanOrEqualTo(2));
    expect(state['timers'], hasLength(1));
    expect(state['timers'][0]['cancelled'], false);
  });
  test(
    'session timer outbox preserves range metadata and consumes an extension',
    () async {
      offline = true;
      final key = 'remote:session:${state['id']}:2';
      final deadline = DateTime.now().add(const Duration(minutes: 1));
      await NativeTimers.schedule(key, deadline, 'Soup', extensionSeconds: 120);
      await sync.refresh();
      expect(sync.timers('${state['id']}').single['extension_seconds'], 120);
      sync.dispose();
      sync = CookingSessions(
        request: request,
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await sync.start();
      offline = false;
      await sync.refresh();
      expect(writes.single['extension_seconds'], 120);
      expect(state['timers'][0]['extension_seconds'], 120);
      await NativeTimers.extend(
        key,
        now: deadline.add(const Duration(seconds: 1)),
      );
      await sync.refresh();
      expect(writes.last['extend'], isTrue);
      expect(writes.last['extension_seconds'], 0);
      expect(state['timers'][0]['extension_seconds'], 0);
    },
  );
  test('native notification actions are durable, idempotent and account/device scoped', () async {
    final operation = {
      'account_uid': null,
      'installation_id': sync.installation,
      'session_id': state['id'],
      'operation_id': 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      'body': {
        'action_id': '2',
        'cancelled': true,
        'revision': 0,
        'extension_seconds': 0,
        'expected_deadline_ms': 1800000000000,
      },
    };
    offline = true;
    await sync.importNativeActions([
      {...operation, 'account_uid': 'another-user'},
      {...operation, 'installation_id': 'another-device'},
    ]);
    expect(sync.timers('${state['id']}'), isEmpty);
    await sync.importNativeActions([operation, operation]);
    expect(sync.timers('${state['id']}').single['cancelled'], isTrue);
    sync.dispose();
    sync = CookingSessions(
      request: request,
      installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await sync.start();
    offline = false;
    await sync.refresh();
    expect(writes, hasLength(1));
    expect(writes.single['operation_id'], operation['operation_id']);
    expect(writes.single['expected_deadline_ms'], 1800000000000);
    expect(state['timers'][0]['extension_seconds'], 0);
  });
  test('ending removes session and carries cancellation state', () async {
    await sync.end('${state['id']}');
    expect(sync.sessions, isEmpty);
  });
  test(
    'old-account replies cannot restore sessions after an account switch',
    () async {
      sync.dispose();
      final accounts = StreamController<String?>();
      final delayed = Completer<Map<String, dynamic>>();
      var delay = false;
      sync = CookingSessions(
        installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        accountChanges: accounts.stream,
        request: (path, {body}) async {
          if (delay && body != null) return delayed.future;
          return {'sessions': <Map<String, dynamic>>[]};
        },
      );
      await sync.start();
      accounts.add('alice');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sync.accept({
        'sessions': [state],
      });
      delay = true;
      final pending = sync.check('${state['id']}', '1', true);
      accounts.add('bob');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      delayed.complete({'session': state});
      await expectLater(pending, throwsStateError);
      expect(sync.sessions, isEmpty);
      await accounts.close();
    },
  );
}
