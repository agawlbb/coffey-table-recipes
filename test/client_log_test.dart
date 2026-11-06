import 'dart:convert';
import 'dart:ui';

import 'package:coffey_table_recipes/src/client_error_logging.dart';
import 'package:coffey_table_recipes/src/client_log.dart';
import 'package:coffey_table_recipes/src/client_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bounded diagnostics survive restart without payloads or credentials',
    () async {
      String? saved;
      ClientLog create() => ClientLog(
        limit: 3,
        read: (_) async => saved,
        write: (_, value) async {
          saved = value;
        },
      );
      final first = create();
      await first.start();
      for (var i = 0; i < 6; i++) {
        first.record(
          'socket',
          'failed',
          error: StateError(
            'Bearer secret-token alice@example.test private recipe',
          ),
          stack: StackTrace.fromString(
            '#0 save (file:///private/alice/local_data.dart:99:1)',
          ),
          path: 'https://alice:secret@server.test/households/12/recipes/42?token=secret-token',
          status: 503,
          code: 'connection_lost',
          pending: i,
        );
      }
      await first.flush();
      final second = create();
      await second.start();
      expect(second.text.split('\n'), hasLength(3));
      expect(second.text, contains('connection_lost'));
      expect(second.text, contains('local_data.dart:99:1'));
      for (final secret in [
        'secret',
        'alice',
        'Bearer',
        'private recipe',
        'server.test',
      ]) {
        expect(second.text, isNot(contains(secret)));
      }
      expect((jsonDecode(saved!) as List).last['pending'], 5);
      first.dispose();
      second.dispose();
    },
  );
  test('authentication and native failures retain safe codes without private messages', () async {
    final log = ClientLog(read: (_) async => null, write: (_, _) async {});
    log.record(
      'auth',
      'token_failed',
      error: FirebaseAuthException(
        code: 'network-request-failed',
        message: 'private credential',
      ),
    );
    log.record(
      'native',
      'operation_failed',
      error: PlatformException(
        code: 'storage_unavailable',
        message: 'private path',
        details: 'secret',
      ),
    );
    expect(log.text, contains('network-request-failed'));
    expect(log.text, contains('storage_unavailable'));
    expect(log.text, isNot(contains('private')));
    expect(log.text, isNot(contains('secret')));
    log.dispose();
  });

  test(
    'diagnostic storage failures keep memory readable and do not escape',
    () async {
      final log = ClientLog(
        read: (_) async => throw StateError('disk'),
        write: (_, _) async => throw StateError('disk'),
      );
      await log.start();
      log.record('storage', 'persist_failed', error: StateError('disk'));
      await log.flush();
      expect(log.text, contains('persist_failed'));
      log.dispose();
    },
  );
  test('uncaught hooks log safely and preserve existing handlers', () async {
    final log = ClientLog(read: (_) async => null, write: (_, _) async {});
    final oldFlutter = FlutterError.onError;
    final oldPlatform = PlatformDispatcher.instance.onError;
    var flutterCalled = false, platformCalled = false;
    FlutterError.onError = (_) {
      flutterCalled = true;
    };
    PlatformDispatcher.instance.onError = (_, _) {
      platformCalled = true;
      return true;
    };
    try {
      installClientErrorLogging(log: log);
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('private')),
      );
      expect(
        PlatformDispatcher.instance.onError!(
          StateError('private'),
          StackTrace.current,
        ),
        true,
      );
      expect(flutterCalled, true);
      expect(platformCalled, true);
      expect(log.text, contains('flutter'));
      expect(log.text, contains('platform'));
      expect(log.text, isNot(contains('private')));
    } finally {
      FlutterError.onError = oldFlutter;
      PlatformDispatcher.instance.onError = oldPlatform;
      log.dispose();
    }
  });
  test(
    'routine events are ignored and old informational rows are removed on load',
    () async {
      final log = ClientLog(
        read: (_) async => jsonEncode([
          {'event': 'started', 'area': 'app'},
          {'event': 'transport_closed', 'area': 'socket', 'status': 1000},
          {
            'time': DateTime.now().toUtc().toIso8601String(),
            'event': 'failed',
            'area': 'sync',
            'status': 503,
          },
        ]),
        write: (_, _) async {},
      );
      await log.start();
      for (final event in [
        'ready',
        'opening',
        'resumed',
        'confirmed',
        'network_online',
      ]) {
        log.record('sync', event, connected: true);
      }
      log.record('socket', 'transport_closed', status: 1000);
      expect(log.text, contains('failed'));
      expect(log.text, isNot(contains('transport_closed')));
      for (final event in [
        'started',
        'ready',
        'opening',
        'resumed',
        'confirmed',
        'network_online',
      ]) {
        expect(log.text, isNot(contains('"event":"$event"')));
      }
      log.version = '2.7.6.61';
      log.record('api', 'save_failed', status: 503);
      expect(log.text, contains('2.7.6.61'));
      log.dispose();
    },
  );
  test('log expires entries and clears once per app version', () async {
    final disk = <String, String>{};
    var clock = DateTime.utc(2026, 11, 6, 12);
    ClientLog create(String version) => ClientLog(
      read: (key) async => disk[key],
      write: (key, value) async {
        disk[key] = value;
      },
      now: () => clock,
    )..version = version;
    final first = create('2.8.1.64');
    await first.start();
    first.record('sync', 'old', status: 503);
    await first.flush();
    clock = clock.add(const Duration(hours: 23));
    first.record('sync', 'recent', status: 503);
    await first.flush();
    first.dispose();
    clock = clock.add(const Duration(hours: 2));
    final same = create('2.8.1.64');
    await same.start();
    expect(same.text, isNot(contains('"event":"old"')));
    expect(same.text, contains('recent'));
    await same.clear();
    expect(same.text, 'No errors recorded.');
    same.record('sync', 'before_update', status: 503);
    await same.flush();
    same.dispose();
    final update = create('2.8.2.65');
    await update.start();
    expect(update.text, 'No errors recorded.');
    update.record('sync', 'after_update', status: 503);
    await update.flush();
    update.dispose();
    final restarted = create('2.8.2.65');
    await restarted.start();
    expect(restarted.text, contains('after_update'));
    restarted.dispose();
  });

  testWidgets('log viewer copies displayed diagnostics to clipboard', (
    tester,
  ) async {
    final log = ClientLog(read: (_) async => null, write: (_, _) async {});
    await log.start();
    log.record(
      'sync',
      'snapshot_failed',
      error: StateError('invalid snapshot'),
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      log.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: ClientLogScreen(log: log)));
    await tester.pumpAndSettle();
    expect(find.text('Error log'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy to clipboard'));
    await tester.pumpAndSettle();
    expect(copied, log.text);
    expect(copied, contains('snapshot_failed'));
    await tester.tap(find.byTooltip('Clear log'));
    await tester.pumpAndSettle();
    expect(find.text('No errors recorded.'), findsOneWidget);
  });
}
