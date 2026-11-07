import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/app_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Platform.environment['CTR_BACKEND_SOURCE'];
  test('token renewal keeps the same open connection and stays connected', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    var opens = 0, authentications = 0;
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      peers.add(ws);
      ws.listen((raw) {
        final frame = jsonDecode(raw as String) as Map;
        if (frame['type'] == 'auth') {
          authentications++;
          ws.add(
            jsonEncode({'type': 'ready', 'household_id': null, 'data': {}}),
          );
        } else if (frame['type'] == 'request') {
          ws.add(
            jsonEncode({'type': 'response', 'id': frame['id'], 'data': {}}),
          );
        }
      });
    });
    String token(int expiry) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'same-user', 'iss': 'fixture', 'aud': 'fixture', 'exp': expiry})))}.signature';
    final connection = AppConnection(
      connect: (_) {
        opens++;
        return WebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:${server.port}'),
        );
      },
      networkChanges: const Stream<bool>.empty(),
    );
    final api = RecipeApi(
      baseUrl: 'https://unused.test',
      connection: connection,
    );
    final states = <bool>[];
    api.onConnectionChanged = () => states.add(connection.connected);
    addTearDown(() async {
      api.close();
      connection.dispose();
      for (final ws in peers) {
        unawaited(ws.close());
      }
      await server.close(force: true);
    });
    await api.request('/me/timers', token(1));
    states.clear();
    await api.request('/me/timers', token(2));
    expect(opens, 1);
    expect(authentications, 2);
    expect(states.every((v) => v), true);
  });

  test('slow and timed-out AI requests do not hold token renewal or other traffic', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    final aiReceived = Completer<void>();
    final renewalReceived = Completer<void>();
    final releaseRenewal = Completer<void>();
    var authentications = 0;
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      peers.add(ws);
      ws.listen((raw) async {
        final frame = jsonDecode(raw as String) as Map;
        if (frame['type'] == 'auth') {
          if (++authentications == 2) {
            renewalReceived.complete();
            await releaseRenewal.future;
          }
          ws.add(
            jsonEncode({'type': 'ready', 'household_id': null, 'data': {}}),
          );
        } else if (frame['type'] == 'request') {
          if (frame['path'] == '/households/1/cooking-plan') {
            aiReceived.complete();
          } else {
            ws.add(
              jsonEncode({
                'type': 'response',
                'id': frame['id'],
                'data': {'ok': true},
              }),
            );
          }
        }
      });
    });
    String token(int expiry) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'same-user', 'exp': expiry})))}.signature';
    var opens = 0;
    final connection = AppConnection(
      connect: (_) {
        opens++;
        return WebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:${server.port}'),
        );
      },
      networkChanges: const Stream<bool>.empty(),
    );
    addTearDown(() async {
      if (!releaseRenewal.isCompleted) releaseRenewal.complete();
      connection.dispose();
      for (final ws in peers) {
        unawaited(ws.close());
      }
      await server.close(force: true);
    });
    await connection.open(token(1));
    final ai = connection.request(
      '/households/1/cooking-plan',
      token(1),
      body: {},
      timeout: const Duration(milliseconds: 200),
    );
    final timedOut = expectLater(ai, throwsA(isA<ApiException>()));
    await aiReceived.future;
    await connection.open(token(2)).timeout(const Duration(seconds: 2));
    await renewalReceived.future.timeout(const Duration(seconds: 2));
    expect(
      await connection
          .request('/me/timers', token(2))
          .timeout(const Duration(seconds: 2)),
      {'ok': true},
    );
    await timedOut;
    expect(
      await connection
          .request('/me/cooking-sessions', token(2))
          .timeout(const Duration(seconds: 2)),
      {'ok': true},
    );
    releaseRenewal.complete();
    expect(opens, 1);
    expect(connection.connected, true);
  });

  test(
    'real Dart app shares one authenticated connection and applies writes and pushes',
    () async {
      final temporary = await Directory.systemTemp.createTemp('ctr-one-wire-');
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final media = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final mediaPort = media.port;
      await media.close();
      final process = await Process.start(
        'setsid',
        ['php', 'tests/fixtures/app_socket_server.php', 'start'],
        workingDirectory: source,
        environment: {
          ...Platform.environment,
          'CTR_LISTEN': 'websocket://127.0.0.1:$port',
          'CTR_MEDIA_LISTEN': 'http://127.0.0.1:$mediaPort',
          'CTR_TEST_DATABASE': '${temporary.path}/data.sqlite',
          'CTR_RUNTIME_DIR': temporary.path,
          'CTR_STORAGE': '${temporary.path}/state',
        },
      );
      final output = StringBuffer();
      process.stdout.listen((b) => output.write(String.fromCharCodes(b)));
      process.stderr.listen((b) => output.write(String.fromCharCodes(b)));
      var opens = 0;
      final connection = AppConnection(
        connect: (_) {
          opens++;
          return WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
        },
        refreshToken: (_) async => 'alice',
        networkChanges: const Stream<bool>.empty(),
      );
      final api = RecipeApi(
        baseUrl: 'https://unused.test',
        connection: connection,
      );
      final cookingApi = RecipeApi(
        baseUrl: 'https://unused.test',
        connection: connection,
      );
      final state = <String, dynamic>{};
      api.onAppSnapshot = (data) async {
        state.addAll(data);
      };
      cookingApi.onAppSnapshot = (data) async {
        state.addAll(data);
      };
      addTearDown(() async {
        api.close();
        cookingApi.close();
        connection.dispose();
        await Process.run('kill', ['-TERM', '--', '-${process.pid}']);
        await process.exitCode;
        await temporary.delete(recursive: true);
      });
      for (var attempt = 0; attempt < 100; attempt++) {
        try {
          final socket = await Socket.connect('127.0.0.1', port);
          socket.destroy();
          break;
        } catch (_) {
          if (attempt == 99) fail('Server did not start: $output');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      await api.request('/me', 'alice');
      await cookingApi.request('/me/cooking-sessions', 'alice');
      await api.request('/me/timers', 'alice');
      expect(opens, 1);
      expect(connection.connected, true);
      await cookingApi.request(
        '/households/1/meal-plan',
        'alice',
        body: {
          'revision': 0,
          'operation': 'add',
          'id': 'one-wire-meal',
          'kind': 'leftovers',
          'date': '2099-11-06',
        },
      );
      expect(
        (state['households']['1']['library']['responses']['/households/1/meal-plan']['entries']
                as List)
            .single['id'],
        'one-wire-meal',
      );
      await Future.wait([
        api.request('/me/name', 'alice', body: {'display_name': 'First name'}),
        cookingApi.request(
          '/me/name',
          'alice',
          body: {'display_name': 'Last name'},
        ),
      ]);
      expect(state['account']['user']['display_name'], 'Last name');
      api.close();
      await cookingApi.request('/me/timers', 'alice');
      expect(opens, 1);
      connection.reconnect();
      await cookingApi.request('/me', 'alice');
      expect(opens, 2);
      expect(
        state['households']['1']['library']['responses']['/households/1/meal-plan']['entries'],
        hasLength(1),
      );
    },
    skip: source == null
        ? 'Set CTR_BACKEND_SOURCE for real PHP transport'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
