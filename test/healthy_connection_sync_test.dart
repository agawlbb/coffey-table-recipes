import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/app_connection.dart';
import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/local_sqlite.dart';

import 'local_first_sqlite_test.dart' show library;
import 'support/sqlite.dart';

Future<void> eventually(bool Function() ready) async {
  for (var i = 0; i < 500 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fail in [false, true]) {
    test(
      'healthy open connection mirrors changes with pending decisions and ${fail ? 'failed' : 'unanswered'} unrelated save',
      () async {
        final directory = await Directory.systemTemp.createTemp('ctr-wire-');
        final db = LocalSqlite(
          factory: sqliteFactory,
          path: '${directory.path}/data.sqlite',
          readLegacy: (_) async => null,
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <WebSocket>[];
        var held = false, shoppingReceived = false, timedOut = false;
        var serverLibrary = library();
        var serverShopping = <String, dynamic>{
          'revision': 0,
          'departments': ['Other'],
          'items': [],
        };
        Map<String, dynamic> snapshot() => {
          'households': {
            '1': {'library': serverLibrary, 'shopping': serverShopping},
          },
        };
        void push(WebSocket ws) => ws.add(
          jsonEncode({
            'type': 'snapshot',
            'household_id': null,
            'data': snapshot(),
          }),
        );
        server.listen((request) async {
          final ws = await WebSocketTransformer.upgrade(request);
          sockets.add(ws);
          ws.listen((raw) {
            final frame = jsonDecode(raw as String) as Map;
            if (frame['type'] == 'auth') {
              ws.add(
                jsonEncode({
                  'type': 'ready',
                  'household_id': null,
                  'data': snapshot(),
                }),
              );
              return;
            }
            if (frame['type'] == 'ping') {
              ws.add(jsonEncode({'type': 'pong'}));
              return;
            }
            if (frame['type'] != 'request') return;
            final path = frame['path'];
            if (path == '/households/1/restaurants') {
              held = true;
              if (fail) {
                ws.add(
                  jsonEncode({
                    'type': 'error',
                    'id': frame['id'],
                    'status': 503,
                    'error': {'code': 'unavailable', 'message': 'Try again'},
                  }),
                );
              }
              return;
            }
            if (path == '/households/1/shopping-list' && frame['body'] is Map) {
              shoppingReceived = true;
              final body = frame['body'] as Map;
              final rows = List<dynamic>.from(serverShopping['items'] as List);
              for (final item in body['upsert_items'] as List? ?? []) {
                rows.removeWhere((e) => e['id'] == item['id']);
                rows.add(item);
              }
              rows.removeWhere(
                (e) => (body['remove_ids'] as List? ?? []).contains(e['id']),
              );
              serverShopping = {...serverShopping, 'items': rows};
              push(ws);
            }
            ws.add(
              jsonEncode({'type': 'response', 'id': frame['id'], 'data': {}}),
            );
          });
        });
        final connection = AppConnection(
          connect: (_) => WebSocketChannel.connect(
            Uri.parse('ws://127.0.0.1:${server.port}'),
          ),
          networkChanges: const Stream<bool>.empty(),
        );
        final api = RecipeApi(
          baseUrl: 'https://unused.test',
          connection: connection,
        );
        final local = LocalData(
          key: 'alice',
          fetch: (p) => api.request(p, 'alice'),
          send: (p, b) => p.endsWith('/restaurants') && !fail
              ? connection.request(
                  p,
                  'alice',
                  body: b,
                  timeout: const Duration(milliseconds: 100),
                )
              : api.request(p, 'alice', body: b),
          readStore: db.read,
          writeStore: db.write,
        )..connected = () => connection.connected;
        local.onSendError = (_, error) {
          if (error is ApiException && error.code == 'response_timeout') {
            timedOut = true;
          }
        };
        api.onAppSnapshot = (data) async {
          for (final h in (data['households'] as Map? ?? {}).entries) {
            await local.acceptShopping(
              '${h.key}',
              Map<String, dynamic>.from(h.value['shopping'] as Map),
            );
            await local.installSnapshot(
              Map<String, dynamic>.from(h.value['library'] as Map),
            );
          }
        };
        try {
          await local.installSnapshot(library());
          await local.save('/households/1/recipes/1', {
            'title': 'My offline soup',
          });
          await local.save('/households/1/meal-plan', {
            'operation': 'move',
            'id': 'meal',
            'date': '2026-11-09',
          });
          await api.connect('alice');
          expect(connection.connected, true);
          expect(local.decisions, hasLength(2));
          await local.save('/households/1/restaurants', {
            'items': [
              {'id': 'r', 'name': 'Cafe'},
            ],
          });
          await eventually(() => held);
          if (!fail) await eventually(() => timedOut);
          await local.save('/households/1/shopping-list', {
            'items': [
              {
                'id': 'bread',
                'name': 'Bread',
                'checked': false,
                'department': 'Other',
              },
            ],
          });
          await eventually(() => shoppingReceived);
          await eventually(
            () => !local.pendingChanges.any(
              (e) => e['path'] == '/households/1/shopping-list',
            ),
          );
          serverLibrary = library(title: 'Their soup');
          (serverLibrary['recipes'] as List).add({
            'id': '2',
            'title': 'Remote salad',
          });
          (serverLibrary['responses'] as Map)['/households/1/recipes/2'] = {
            'recipe': {
              'id': '2',
              'title': 'Remote salad',
              'category_assignments': [],
            },
          };
          (serverLibrary['responses']['/households/1/meal-plan']['entries']
                  as List)
              .add({
                'id': 'other',
                'kind': 'leftovers',
                'title': 'Other meal',
                'plan_date': '2026-11-11',
              });
          push(sockets.single);
          await eventually(() {
            try {
              return local.readView(
                    '/households/1/recipes/2',
                  )['recipe']['title'] ==
                  'Remote salad';
            } catch (_) {
              return false;
            }
          });
          expect(
            local.readView('/households/1/recipes/1')['recipe']['title'],
            'My offline soup',
          );
          expect(
            local.readView('/households/1/meal-plan')['entries'],
            hasLength(2),
          );
          expect(local.decisions, hasLength(2));
          expect(connection.connected, true);
          await local.decide(local.decisions.first['id'] as String, false);
          expect(
            local.readView('/households/1/recipes/1')['recipe']['title'],
            'Their soup',
          );
          expect(connection.connected, true);
        } finally {
          local.dispose();
          api.close();
          connection.dispose();
          for (final ws in sockets) {
            unawaited(ws.close());
          }
          await server.close(force: true);
          await db.close();
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
