import 'package:coffey_table_recipes/src/ai_progress.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/shopping_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recipe, meal and timer traffic uses authenticated sockets; AI progress use sockets; signup stays HTTP', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final frames = <Map<String, dynamic>>[];
    final peers = <WebSocket>[];
    final timerPush = Completer<Map<String, dynamic>>();
    server.listen((request) async {
      expect(request.uri.query, isEmpty);
      final peer = await WebSocketTransformer.upgrade(request);
      peers.add(peer);
      peer.listen((raw) {
        final frame = Map<String, dynamic>.from(
          jsonDecode(raw as String) as Map,
        );
        frames.add(frame);
        if (frame['type'] == 'auth') {
          peer.add(
            jsonEncode({
              'type': 'ready',
              'household_id': frame['household_id'],
              'data': frame['scope'] == 'timers' ? {'timers': []} : {},
            }),
          );
        } else if (frame['type'] == 'request') {
          if (isAiPath(frame['path'] as String)) {
            peer.add(
              jsonEncode({
                'type': 'progress',
                'id': frame['id'],
                'message': 'Checking draft…',
                'elapsed_seconds': 12,
              }),
            );
          }
          peer.add(
            jsonEncode({
              'type': 'response',
              'id': frame['id'],
              'data': {'path': frame['path']},
            }),
          );
          if (frame['path'] == '/me/timers') {
            peer.add(
              jsonEncode({
                'type': 'snapshot',
                'household_id': null,
                'data': {
                  'timers': [
                    {'timer_id': 'remote'},
                  ],
                },
              }),
            );
          }
        }
      });
    });
    final httpPaths = <String>[];
    final api = RecipeApi(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        httpPaths.add(request.url.path);
        return http.Response('{}', 200);
      }),
      socketConnect: (_) => WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/shopping'),
      ),
    );
    api.onTimerSnapshot = (data) async {
      if ((data['timers'] as List).isNotEmpty && !timerPush.isCompleted) {
        timerPush.complete(data);
      }
    };
    addTearDown(() async {
      api.close();
      for (final peer in peers) {
        await peer.close();
      }
      await server.close(force: true);
    });
    for (final path in [
      '/households/1/recipes?q=soup',
      '/households/1/meal-plan?from=2099-01-01&to=2099-01-07',
      '/households/1/snapshot',
      '/households/1/recipes/2',
    ]) {
      expect((await api.request(path, 'fixture'))['path'], path);
    }
    await api.request(
      '/households/1/recipes/2',
      'fixture',
      body: {'client_save_id': 'stable', 'title': 'Soup'},
    );
    await api.request(
      '/me/timers',
      'fixture',
      body: {'operation_id': 'stable-timer'},
    );
    expect((await timerPush.future)['timers'], [
      {'timer_id': 'remote'},
    ]);
    await api.request('/households/1/name', 'fixture', body: {'name': 'Table'});
    await api.request(
      '/households/1/people/me/name',
      'fixture',
      body: {'display_name': 'Alice'},
    );
    await api.request('/recipes/2', '');
    await api.request('/me', 'fixture');
    final progress = AiRunProgress();
    addTearDown(progress.dispose);
    final messages = <String?>[];
    progress.addListener(() => messages.add(progress.value));
    await progress.run(
      () => api.request('/households/1/recipe-import', 'fixture', body: {}),
    );
    expect(messages, ['Checking draft… (12 s)', null]);
    await api.request(
      '/households/1/recipe-import',
      'fixture',
      body: {'kind': 'answers', 'answers': []},
    );
    await api.request('/households/1/recipes/2/variation', 'fixture', body: {});
    expect(httpPaths, ['/me']);
    final auth = frames.where((f) => f['type'] == 'auth').toList();
    expect(auth.map((f) => f['scope']), [
      'household',
      'timers',
      'public',
      'ai',
    ]);
    expect(auth.first['token'], 'fixture');
    final edit = frames.firstWhere(
      (f) => (f['body'] as Map?)?['client_save_id'] == 'stable',
    );
    expect(edit['body'], {'client_save_id': 'stable', 'title': 'Soup'});
  });

  test(
    'household readiness waits for both shopping and library persistence',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final persisted = Completer<void>();
      final received = Completer<void>();
      server.listen((request) async {
        final peer = await WebSocketTransformer.upgrade(request);
        peer.listen((raw) {
          final frame = jsonDecode(raw as String) as Map;
          if (frame['type'] == 'auth') {
            expect(frame['scope'], 'household');
            peer.add(
              jsonEncode({
                'type': 'ready',
                'household_id': '1',
                'data': {
                  'shopping': {'items': []},
                  'library': {'version': 'v1'},
                },
              }),
            );
          } else if (frame['type'] == 'request') {
            if (isAiPath(frame['path'] as String)) {
              peer.add(
                jsonEncode({
                  'type': 'progress',
                  'id': frame['id'],
                  'message': 'Checking draft…',
                  'elapsed_seconds': 12,
                }),
              );
            }
            peer.add(
              jsonEncode({'type': 'response', 'id': frame['id'], 'data': {}}),
            );
          }
        });
      });
      final socket = ShoppingSocket(
        household: '1',
        scope: 'household',
        token: (_) async => 'fixture',
        url: 'ws://127.0.0.1:${server.port}',
        onSnapshot: (data) async {
          expect(data.keys, containsAll(['shopping', 'library']));
          received.complete();
          await persisted.future;
        },
      );
      addTearDown(() async {
        socket.dispose();
        await server.close(force: true);
      });
      socket.start();
      await received.future;
      expect(socket.connected, false);
      persisted.complete();
      await socket.request('/households/1/recipes');
      expect(socket.connected, true);
      await expectLater(
        socket.request('/households/2/recipes'),
        throwsArgumentError,
      );
      await expectLater(socket.request('/me/timers'), throwsArgumentError);
    },
  );
}
