import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:coffey_table_recipes/src/connection_indicator.dart';
import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/shopping_socket.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'home_design_test.dart' show TestUser;
import 'snapshot_database_test.dart' show snapshot;

class SyncUser extends TestUser {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'fixture-token';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real account coordinator retains initial and reconnected snapshot confirmation',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ctr-coordinator-'),
      ))!;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (_) async => ['wifi'],
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
        (_) async => null,
      );
      final peers = <WebSocket>[];
      final householdPeers = <WebSocket>[];
      late HttpServer server;
      var title = 'First canonical recipe';
      var holdSnapshotReads = true;
      final held = <Map<String, dynamic>>[];
      Map<String, dynamic> library() {
        final data = snapshot(title);
        data['user']['id'] = '42';
        data['responses']['/households/1/meal-plan'] = {
          'revision': 1,
          'entries': [],
        };
        data['responses']['/households/1/meal-plan/history'] = {'entries': []};
        data['responses']['/households/1/restaurants'] = {
          'revision': 1,
          'items': [],
        };
        return data;
      }

      Map<String, dynamic> state() => {
        'shopping': {'revision': 1, 'items': [], 'departments': []},
        'library': library(),
      };
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final ws = await WebSocketTransformer.upgrade(request);
          peers.add(ws);
          ws.listen((raw) {
            final m = jsonDecode(raw as String) as Map;
            if (m['type'] == 'auth') {
              final household = m['scope'] == 'household';
              if (household) householdPeers.add(ws);
              ws.add(
                jsonEncode({
                  'type': 'ready',
                  'household_id': household ? '1' : null,
                  'data': household ? state() : {},
                }),
              );
            } else if (m['type'] == 'request') {
              final path = m['path'] as String;
              if (path.endsWith('/snapshot') && holdSnapshotReads) {
                held.add({'socket': ws, 'id': m['id']});
                return;
              }
              final data = path == '/me'
                  ? {
                      'user': {
                        'id': '42',
                        'display_name': 'Alice',
                        'child_mode': false,
                      },
                      'households': [
                        {'id': '1', 'name': 'Table', 'role': 'owner'},
                      ],
                      'invitations': [],
                    }
                  : path == '/me/child-mode'
                  ? {'enabled': false}
                  : path.endsWith('/snapshot')
                  ? library()
                  : {'people': []};
              ws.add(
                jsonEncode({'type': 'response', 'id': m['id'], 'data': data}),
              );
            }
          });
        });
      });
      addTearDown(() async {
        for (final ws in peers) {
          unawaited(ws.close());
        }
        await server.close(force: true);
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          null,
        );
        await directory.delete(recursive: true);
        connectedHouseholds.value = {};
        pendingSyncMessage.value = null;
        offlineStatus.value = false;
      });
      Future<void> settleUntil(bool Function() done) async {
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await tester.pump(const Duration(milliseconds: 20));
          if (done()) return;
        }
        fail(
          'Sync did not settle: ${pendingSyncMessage.value}, connected=${connectedHouseholds.value}',
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(
            user: SyncUser(),
            readPreference: (_) async => null,
            writePreference: (_, _) async {},
            socketConnect: (_) => WebSocketChannel.connect(
              Uri.parse('ws://127.0.0.1:${server.port}'),
            ),
          ),
        ),
      );
      try {
        await settleUntil(
          () =>
              connectedHouseholds.value.contains('1') &&
              pendingSyncMessage.value == null,
        );
        expect(householdPeers, hasLength(1));
        holdSnapshotReads = false;
        for (final row in held) {
          (row['socket'] as WebSocket).add(
            jsonEncode({
              'type': 'response',
              'id': row['id'],
              'data': library(),
            }),
          );
        }
        title = 'Remote recipe update';
        householdPeers.last.add(
          jsonEncode({
            'type': 'snapshot',
            'household_id': '1',
            'data': state(),
          }),
        );
        await settleUntil(
          () =>
              find.text('Remote recipe update').evaluate().isNotEmpty &&
              pendingSyncMessage.value == null,
        );
        await tester.runAsync(() async {
          await householdPeers.last.close();
        });
        await settleUntil(() => !connectedHouseholds.value.contains('1'));
        await settleUntil(
          () =>
              householdPeers.length == 2 &&
              connectedHouseholds.value.contains('1') &&
              pendingSyncMessage.value == null,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump();
      }
    },
  );

  test(
    'snapshot confirmations survive notifications before socket ready',
    () async {
      final local = LocalData(
        key: 'ready-order',
        fetch: (_) async => {},
        send: (_, _) async => {},
        readStore: (_) async => null,
        writeStore: (_, _) async {},
        snapshotOnly: true,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      server.listen((request) async {
        final peer = await WebSocketTransformer.upgrade(request);
        peers.add(peer);
        peer.listen((raw) {
          final m = jsonDecode(raw as String) as Map;
          if (m['type'] == 'auth') {
            peer.add(
              jsonEncode({
                'type': 'ready',
                'household_id': '1',
                'data': snapshot('canonical'),
              }),
            );
          }
        });
      });
      final ready = Completer<void>();
      final socket = ShoppingSocket(
        household: '1',
        scope: 'household',
        token: (_) async => 'fixture',
        url: 'ws://127.0.0.1:${server.port}',
        onSnapshot: local.installSnapshot,
        onDisconnect: () => local.invalidateConfirmation('1'),
        onReady: () => ready.complete(),
      );
      addTearDown(() async {
        socket.dispose();
        local.dispose();
        for (final p in peers) {
          unawaited(p.close());
        }
        await server.close(force: true);
      });
      // Observe exactly the account header's synchronous state notifications.
      var appliedBeforeReady = false;
      local.addListener(() {
        if (local.isHouseholdConfirmed('1') && !socket.connected) {
          appliedBeforeReady = true;
        }
      });
      socket.start();
      await ready.future.timeout(const Duration(seconds: 3));
      expect(appliedBeforeReady, true);
      expect(local.isHouseholdConfirmed('1'), true);
      socket.reconnect();
      expect(local.isHouseholdConfirmed('1'), false);
    },
  );
}
