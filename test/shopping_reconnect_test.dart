import 'package:coffey_table_recipes/src/ai_progress.dart';

import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/shopping_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _path = '/households/1/shopping-list';
Map<String, dynamic> _state(int revision) => {
  'revision': revision,
  'items': <Map<String, dynamic>>[],
  'departments': ['Other'],
};

class _Channel implements WebSocketChannel {
  _Channel({bool ready = true, this.onSend}) {
    if (ready) handshake.complete();
  }
  final handshake = Completer<void>();
  final incoming = StreamController<dynamic>();
  final messages = <Map<String, dynamic>>[];
  final void Function(Map<String, dynamic>)? onSend;
  @override
  Future<void> get ready => handshake.future;
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  late final WebSocketSink sink = _Sink((raw) {
    final message = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
    messages.add(message);
    onSend?.call(message);
  });
  void receive(Map<String, dynamic> message) =>
      incoming.add(jsonEncode(message));
  void authenticate(int revision) =>
      receive({'type': 'ready', 'household_id': '1', 'data': _state(revision)});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  _Sink(this.send);
  final void Function(dynamic) send;
  bool closed = false;
  @override
  void add(dynamic data) {
    if (closed) throw StateError('Closed socket');
    send(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Wi-Fi restoration replaces a stalled token attempt immediately',
    (tester) async {
      final network = StreamController<bool>();
      final first = Completer<String?>(), second = Completer<String?>();
      final peers = <_Channel>[];
      var calls = 0;
      final socket = ShoppingSocket(
        household: '1',
        networkChanges: network.stream,
        token: (_) => ++calls == 1 ? first.future : second.future,
        connect: (_) {
          final peer = _Channel();
          peers.add(peer);
          return peer;
        },
        onSnapshot: (_) async {},
      );
      socket.start();
      await tester.pump();
      network.add(false);
      network.add(true);
      await tester.pump();
      expect(calls, 2); // Does not wait for the old ten-second token timeout.
      first.complete('stale');
      await tester.pump();
      socket.start();
      expect(
        calls,
        2,
      ); // Old finally must not clear the new attempt's opening flag.
      second.complete('current');
      await tester.pump();
      expect(peers.single.messages.single['token'], 'current');
      peers.single.authenticate(1);
      await tester.pump();
      expect(socket.connected, isTrue);
      await tester.pump(const Duration(seconds: 6));
      expect(calls, 2); // The old retry timer was cancelled.
      socket.dispose();
      unawaited(network.close());
      await tester.pump();
    },
  );

  testWidgets('Wi-Fi restoration bypasses a stalled WebSocket handshake', (
    tester,
  ) async {
    final network = StreamController<bool>();
    final peers = <_Channel>[];
    final socket = ShoppingSocket(
      household: '1',
      networkChanges: network.stream,
      token: (_) async => 'fixture',
      onSnapshot: (_) async {},
      connect: (_) {
        final peer = _Channel(ready: peers.isNotEmpty);
        peers.add(peer);
        return peer;
      },
    );
    socket.start();
    await tester.pump();
    network.add(false);
    network.add(true);
    await tester.pump();
    expect(peers, hasLength(2));
    peers.last.authenticate(1);
    await tester.pump();
    expect(socket.connected, isTrue);
    peers.first.handshake.complete();
    await tester.pump();
    expect(peers.first.messages, isEmpty);
    expect(socket.connected, isTrue);
    socket.dispose();
    unawaited(network.close());
    await tester.pump();
  });

  testWidgets(
    'late snapshots cannot authenticate a replacement; repeated toggles recover',
    (tester) async {
      final network = StreamController<bool>();
      final peers = <_Channel>[];
      final oldPersist = Completer<void>();
      var readyCount = 0;
      final socket = ShoppingSocket(
        household: '1',
        networkChanges: network.stream,
        token: (_) async => 'fixture',
        onSnapshot: (state) =>
            state['revision'] == 1 ? oldPersist.future : Future.value(),
        onReady: () => readyCount++,
        connect: (_) {
          final peer = _Channel();
          peers.add(peer);
          return peer;
        },
      );
      socket.start();
      await tester.pump();
      peers.first.authenticate(1);
      await tester.pump();
      network.add(false);
      network.add(true);
      await tester.pump();
      expect(socket.connected, isFalse);
      expect(readyCount, 0);
      peers.last.authenticate(2);
      await tester.pump();
      expect(socket.connected, isTrue); // Does not wait for the old snapshot.
      expect(readyCount, 1);
      oldPersist.complete();
      await tester.pump();
      expect(readyCount, 1); // Late completion cannot announce another ready.
      for (var i = 0; i < 3; i++) {
        network.add(false);
        await tester.pump();
        expect(socket.connected, isFalse);
        network.add(true);
        await tester.pump();
        peers.last.authenticate(3 + i);
        await tester.pump();
        expect(socket.connected, isTrue);
      }
      final count = peers.length;
      network.add(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(peers, hasLength(count));
      expect(readyCount, 4);
      socket.dispose();
      network.add(false);
      network.add(true);
      await tester.pump();
      expect(peers, hasLength(count));
      unawaited(network.close());
      await tester.pump();
    },
  );

  testWidgets(
    'long outages cap retries at five seconds and resume resets backoff',
    (tester) async {
      var attempts = 0;
      var refresh = false;
      final socket = ShoppingSocket(
        household: '1',
        token: (force) async {
          attempts++;
          refresh = force;
          throw StateError('Offline');
        },
        onSnapshot: (_) async {},
      );
      socket.start();
      await tester.pump();
      expect(attempts, 1);
      for (final seconds in [1, 2, 4, 5, 5, 5]) {
        await tester.pump(Duration(seconds: seconds));
      }
      expect(attempts, 7);
      socket.reconnect();
      await tester.pump(); // Same hook used on app resume.
      expect(attempts, 8);
      expect(refresh, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(attempts, 9);
      socket.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'reconnect replays a lost-response edit immediately with the same ID',
    (tester) async {
      final network = StreamController<bool>();
      final writes = <Map<String, dynamic>>[];
      final disk = <String, String>{};
      var dropResponse = true;
      late final ShoppingSocket socket;
      final data = LocalData(
        key: 'reconnect-replay',
        separateShopping: true,
        online: () => false,
        canSend: (_) => socket.connected,
        fetch: (path) => socket.request(path),
        send: (path, body) => socket.request(path, body: body),
        readStore: (key) async => disk[key],
        writeStore: (key, value) async {
          disk[key] = value;
        },
      );
      socket = ShoppingSocket(
        household: '1',
        networkChanges: network.stream,
        token: (_) async => 'fixture',
        onSnapshot: (state) => data.acceptShopping('1', state),
        onReady: () => unawaited(data.synchronize()),
        connect: (_) {
          late final _Channel peer;
          peer = _Channel(
            onSend: (message) {
              if (message['type'] == 'auth') peer.authenticate(1);
              if (message['type'] == 'request') {
                final body = Map<String, dynamic>.from(message['body'] as Map);
                writes.add(body);
                if (!dropResponse) {
                  peer.receive({
                    'type': 'response',
                    'id': message['id'],
                    'data': {
                      ..._state(2),
                      'items': body['items'],
                      'acknowledged_change_id': body['client_change_id'],
                    },
                  });
                }
              }
            },
          );
          return peer;
        },
      );
      socket.start();
      await tester.pump();
      expect(socket.connected, isTrue);
      await data.save(_path, {
        'revision': 1,
        'items': [
          {'id': 'milk', 'name': 'Milk', 'checked': false, 'department': ''},
        ],
      });
      await tester.pump();
      expect(writes, hasLength(1));
      network.add(false);
      await tester.pump();
      expect(data.pending, 1);
      dropResponse = false;
      network.add(true);
      await tester.pump();
      expect(socket.connected, isTrue);
      expect(writes, hasLength(2));
      expect(writes.last['client_change_id'], writes.first['client_change_id']);
      expect(data.pending, 0); // No twenty-second periodic sync wait.
      expect((await data.cached(_path))!['items'], hasLength(1));
      socket.dispose();
      data.dispose();
      unawaited(network.close());
      await tester.pump();
    },
  );
  testWidgets(
    'AI progress keeps a long request alive and the same socket accepts clarification',
    (tester) async {
      late _Channel channel;
      channel = _Channel(
        onSend: (message) {
          if (message['type'] == 'auth') {
            channel.receive({
              'type': 'ready',
              'household_id': '1',
              'data': <String, dynamic>{},
            });
          } else if (message['type'] == 'ping') {
            channel.receive({'type': 'pong'});
          }
        },
      );
      final socket = ShoppingSocket(
        household: '1',
        scope: 'ai',
        token: (_) async => 'fixture',
        connect: (_) => channel,
        onSnapshot: (_) async {},
      );
      final progress = AiRunProgress();
      var complete = false;
      final request = progress.run(
        () => socket.request(
          '/households/1/recipe-import',
          body: {'kind': 'text', 'text': 'Soup'},
        ),
      );
      unawaited(
        request.then((_) {
          complete = true;
        }),
      );
      await tester.pump();
      final id = channel.messages.firstWhere(
        (m) => m['type'] == 'request',
      )['id'];
      // More than both the previous HTTP limit and the ordinary data socket limit.
      for (var step = 1; step <= 8; step++) {
        channel.receive({
          'type': 'progress',
          'id': id,
          'message': 'Preparing recipe…',
          'elapsed_seconds': step * 20,
        });
        await tester.pump(const Duration(seconds: 20));
        expect(complete, isFalse);
        expect(progress.value, 'Preparing recipe… (${step * 20} s)');
        expect(socket.connected, isTrue);
      }
      channel.receive({
        'type': 'response',
        'id': id,
        'data': {
          'questions': ['How much water?'],
        },
      });
      await tester.pump();
      expect((await request)['questions'], ['How much water?']);
      expect(progress.value, isNull);
      final followup = socket.request(
        '/households/1/recipe-import',
        body: {
          'kind': 'answers',
          'answers': ['One cup'],
        },
      );
      await tester.pump();
      final next = channel.messages.lastWhere((m) => m['type'] == 'request');
      channel.receive({
        'type': 'response',
        'id': next['id'],
        'data': {'questions': <String>[]},
      });
      await tester.pump();
      expect((await followup)['questions'], isEmpty);
      expect(channel.messages.where((m) => m['type'] == 'auth'), hasLength(1));
      socket.dispose();
      progress.dispose();
      await tester.pump();
    },
  );
}
