import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/shopping_socket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial online notification does not interrupt verification delivery', () async {
    final network = StreamController<bool>(sync: true);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    var sends = 0;
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      peers.add(ws);
      ws.listen((raw) async {
        final frame = jsonDecode(raw as String) as Map;
        if (frame['type'] == 'auth') {
          ws.add(
            jsonEncode({'type': 'ready', 'household_id': null, 'data': {}}),
          );
        } else if (frame['type'] == 'request') {
          sends++;
          // Android reports the current network when a new subscription starts.
          network.add(true);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          ws.add(
            jsonEncode({
              'type': 'response',
              'id': frame['id'],
              'data': {'sent': true},
            }),
          );
        }
      });
    });
    final socket = ShoppingSocket(
      household: '',
      scope: 'account',
      token: (_) async => 'new-user',
      url: 'ws://127.0.0.1:${server.port}',
      onSnapshot: (_) async {},
      networkChanges: network.stream,
    );
    addTearDown(() async {
      socket.dispose();
      await network.close();
      for (final peer in peers) {
        await peer.close();
      }
      await server.close(force: true);
    });
    expect(await socket.request('/me/verification-email', body: {}), {
      'sent': true,
    });
    expect(sends, 1);
    expect(socket.connected, isTrue);
    final lost = Completer<void>();
    socket.addListener(() {
      if (!socket.connected && !lost.isCompleted) lost.complete();
    });
    network.add(false);
    await lost.future;
    expect(socket.connected, isFalse);
    network.add(true);
    expect(await socket.request('/me/verification-email', body: {}), {
      'sent': true,
    });
    expect(sends, 2); // Recovery only submits the explicit second request.
  });
  test(
    'ready requires authentication and durable snapshot; disconnect clears it',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final persisted = Completer<void>();
      final auth = Completer<Map>();
      final peer = Completer<WebSocket>();
      server.listen((request) async {
        expect(request.uri.query, isEmpty); // No token in URLs or proxy logs.
        final ws = await WebSocketTransformer.upgrade(request);
        peer.complete(ws);
        ws.listen((raw) {
          final message = jsonDecode(raw as String) as Map;
          if (message['type'] == 'auth') {
            auth.complete(message);
            ws.add(
              jsonEncode({
                'type': 'ready',
                'household_id': '1',
                'data': {'revision': 1},
              }),
            );
          } else if (message['type'] == 'request') {
            ws.add(
              jsonEncode({
                'type': 'response',
                'id': message['id'],
                'data': {'revision': 2, 'acknowledged_change_id': 'stable'},
              }),
            );
          }
        });
      });
      final socket = ShoppingSocket(
        household: '1',
        token: (_) async => 'fixture-token',
        url: 'ws://127.0.0.1:${server.port}',
        onSnapshot: (_) => persisted.future,
      );
      addTearDown(() async {
        socket.dispose();
        await server.close(force: true);
      });
      socket.start();
      expect((await auth.future)['token'], 'fixture-token');
      expect(socket.connected, false);
      persisted.complete();
      final response = await socket.request(
        '/households/1/shopping-list',
        body: {'client_change_id': 'stable'},
      );
      expect(socket.connected, true);
      expect(response['acknowledged_change_id'], 'stable');
      final disconnected = Completer<void>();
      socket.addListener(() {
        if (!socket.connected && !disconnected.isCompleted) {
          disconnected.complete();
        }
      });
      await (await peer.future).close();
      await disconnected.future;
      expect(socket.connected, false);
    },
  );

  test(
    'authorization errors fail pending writes without HTTP fallback',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.listen((raw) {
          final m = jsonDecode(raw as String) as Map;
          ws.add(
            jsonEncode(
              m['type'] == 'auth'
                  ? {'type': 'ready', 'household_id': '1', 'data': {}}
                  : {
                      'type': 'error',
                      'id': m['id'],
                      'status': 403,
                      'error': {'message': 'Access removed'},
                    },
            ),
          );
        });
      });
      final socket = ShoppingSocket(
        household: '1',
        token: (_) async => 'fixture',
        url: 'ws://127.0.0.1:${server.port}',
        onSnapshot: (_) async {},
      );
      addTearDown(() async {
        socket.dispose();
        await server.close(force: true);
      });
      await expectLater(
        socket.request('/households/1/shopping-list', body: {}),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      expect(socket.connected, false);
    },
  );
}
