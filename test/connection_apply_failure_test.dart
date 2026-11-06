import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/app_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a failed incoming update leaves readiness and reconnects to fresh server state', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    var received = 0;
    server.listen((request) async {
      final peer = await WebSocketTransformer.upgrade(request);
      peers.add(peer);
      peer.listen(
        (_) => peer.add(
          jsonEncode({
            'type': 'ready',
            'household_id': null,
            'data': {'fresh': peers.length},
          }),
        ),
      );
    });
    final connection = AppConnection(
      connect: (_) =>
          WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:${server.port}')),
      networkChanges: const Stream<bool>.empty(),
      refreshToken: (_) async => 'fixture',
    );
    connection.addReceiver((state) async {
      if (++received == 1) throw const FormatException('Cannot apply update');
    });
    final ready = Completer<void>();
    connection.addListener(() {
      if (connection.connected && !ready.isCompleted) ready.complete();
    });
    addTearDown(() async {
      connection.dispose();
      for (final peer in peers) {
        unawaited(peer.close());
      }
      await server.close(force: true);
    });
    await expectLater(connection.open('fixture'), throwsA(isA<ApiException>()));
    expect(connection.connected, false);
    await ready.future.timeout(const Duration(seconds: 8));
    expect(peers, hasLength(2));
    expect(connection.data['fresh'], 2);
    expect(connection.connected, true);
  });
}
