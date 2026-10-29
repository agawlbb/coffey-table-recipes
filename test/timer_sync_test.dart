import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/native_timers.dart';
import 'package:coffey_table_recipes/src/timer_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> native;
  late Map<String, int> revisions;
  late List<Map<String, dynamic>> published;
  late List<Map<String, dynamic>> remote;
  late bool offline;
  late String? currentUid;
  late StreamController<String?> accounts;
  late TimerSync sync;
  late RecipeApi api;
  var pushDuringUnregister = false;
  late int permissions;

  Future<void> create() async {
    accounts = StreamController<String?>();
    sync = TimerSync(
      preferences: SharedPreferencesAsync.new,
      api: api = RecipeApi(
        baseUrl: 'https://fixture/api',
        client: MockClient((request) async {
          if (offline) throw http.ClientException('Offline');
          if (request.url.path.endsWith('timer-devices/remove')) {
            if (pushDuringUnregister) {
              await api.onTimerSnapshot?.call({
                'timers': [
                  {'timer_id': 'old-account-timer'},
                ],
              });
            }
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('timer-devices')) {
            return http.Response('{}', 200);
          }
          if (request.method == 'POST') {
            final operation = jsonDecode(request.body) as Map<String, dynamic>;
            published.add(operation);
            return http.Response(
              jsonEncode({
                'timer': {
                  ...operation,
                  'revision': (operation['revision'] as int) + 1,
                },
                'delivery': 'sent',
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'timers': remote}), 200);
        }),
      ),
      currentUid: () => currentUid,
      idToken: () async => 'fixture-auth',
      pushToken: () async => 'fixture-push-token-long-enough',
      authorizeReceiving: () async {
        permissions++;
      },
      accountChanges: () => accounts.stream,
      tokenChanges: () => const Stream.empty(),
    );
    await sync.start();
    accounts.add(currentUid);
    await Future<void>.delayed(Duration.zero);
    try {
      await sync.syncNow();
    } catch (_) {}
  }

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    native = [];
    revisions = {};
    published = [];
    remote = [];
    offline = false;
    pushDuringUnregister = false;
    currentUid = 'val';
    permissions = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTimers.channel, (call) async {
          native.add(call);
          if (call.method == 'list') return [];
          if (call.method == 'syncRevision') {
            return revisions[(call.arguments as Map)['timer_id']] ?? 0;
          }
          if (call.method == 'recordSyncRevision') {
            final args = call.arguments as Map;
            revisions[args['timer_id'] as String] = args['revision'] as int;
          }
          return null;
        });
    await create();
  });

  tearDown(() async {
    await sync.dispose();
    await accounts.close();
    NativeTimers.active.value = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTimers.channel, null);
  });

  test(
    'receiving defaults off and persists only after explicit opt-in',
    () async {
      expect(sync.receiving.value, false);
      expect(permissions, 0);
      await sync.setReceiving(true);
      expect(permissions, 1);
      expect(sync.receiving.value, true);
      expect(
        await SharedPreferencesAsync().getBool('receive_timers_val'),
        true,
      );
      offline = true;
      await sync.setReceiving(false);
      expect(sync.receiving.value, false);
      expect(
        await SharedPreferencesAsync().getBool('receive_timers_val'),
        false,
      );
      expect(
        (native.lastWhere((call) => call.method == 'configureSync').arguments
            as Map)['receive_timers'],
        false,
      );
    },
  );

  test(
    'offline timers survive restart and publish with unchanged deadlines',
    () async {
      offline = true;
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      await NativeTimers.schedule('42:step', deadline, 'Soup');
      expect(
        NativeTimers.active.value.single['deadline'],
        deadline.millisecondsSinceEpoch,
      );
      expect(
        (jsonDecode(
          (await SharedPreferencesAsync().getString('timer_outbox_val'))!,
        ) as List),
        hasLength(1),
      );
      await sync.dispose();
      await accounts.close();
      offline = false;
      await create();
      expect(published, hasLength(1));
      expect(published.single['deadline_ms'], deadline.millisecondsSinceEpoch);
      expect(published.single['revision'], 0);
      expect(published.single['timer_id'], endsWith(':42:step'));
      expect(
        jsonDecode(
          (await SharedPreferencesAsync().getString('timer_outbox_val'))!,
        ),
        isEmpty,
      );
    },
  );

  test(
    'cancellation of received timer retains its shared identity and revision',
    () async {
      revisions['origin:42:step'] = 3;
      await NativeTimers.cancel('remote:origin:42:step');
      await sync.syncNow();
      expect(published.single['timer_id'], 'origin:42:step');
      expect(published.single['revision'], 3);
      expect(published.single['cancelled'], true);
    },
  );

  test(
    'reconciliation binds incoming timers to this account and installation',
    () async {
      remote = [
        {
          'timer_id': 'other:42:step',
          'source_device': 'other',
          'deadline_ms': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'title': 'Soup',
          'revision': 2,
          'cancelled': false,
        },
      ];
      await sync.syncNow();
      final args =
          native.lastWhere((call) => call.method == 'applyRemote').arguments
              as Map;
      expect(args['account_uid'], 'val');
      expect(
        args['target_device'],
        await SharedPreferencesAsync().getString('timer_installation'),
      );
      expect(published, isEmpty); // Reception never echoes a new timer back.
    },
  );

  test(
    'sign-out disables reception even when server unregister is offline',
    () async {
      await sync.setReceiving(true);
      offline = true;
      currentUid = null;
      accounts.add(null);
      await Future<void>.delayed(Duration.zero);
      await sync.syncNow();
      expect(sync.signedIn.value, false);
      expect(sync.receiving.value, false);
      final args =
          native.lastWhere((call) => call.method == 'configureSync').arguments
              as Map;
      expect(args['account_uid'], '');
      expect(args['receive_timers'], false);
      await NativeTimers.schedule(
        '42:other',
        DateTime.now().add(const Duration(minutes: 2)),
        'Other',
      );
      expect(published, isEmpty);
    },
  );

  test(
    'account switch rejects unregister pushes and delayed old snapshots',
    () async {
      final oldSnapshot = api.onTimerSnapshot!;
      native.clear();
      pushDuringUnregister = true;
      currentUid = 'other';
      accounts.add(currentUid);
      await Future<void>.delayed(Duration.zero);
      await sync.syncNow();
      await oldSnapshot({
        'timers': [
          {'timer_id': 'delayed-old-account-timer'},
        ],
      });
      expect(native.where((call) => call.method == 'applyRemote'), isEmpty);
      await api.onTimerSnapshot!({
        'timers': [
          {'timer_id': 'new-account-timer'},
        ],
      });
      final applied =
          native.singleWhere((call) => call.method == 'applyRemote').arguments
              as Map;
      expect(applied['account_uid'], 'other');
      expect(applied['timer_id'], 'new-account-timer');
    },
  );

  test('failed native scheduling never publishes a timer', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeTimers.channel, (call) async {
          if (call.method == 'schedule') {
            throw PlatformException(code: 'permission');
          }
          return null;
        });
    await expectLater(
      NativeTimers.schedule(
        '42:step',
        DateTime.now().add(const Duration(minutes: 5)),
        'Soup',
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(published, isEmpty);
    expect(
      await SharedPreferencesAsync().getString('timer_outbox_val'),
      isNull,
    );
  });
}
