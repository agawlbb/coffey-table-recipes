import 'package:coffey_table_recipes/src/local_sqlite.dart';

import 'support/sqlite.dart';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_store_io.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:coffey_table_recipes/src/connection_indicator.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
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
  for (final decision in [null, 'discard', 'save', 'shared']) {
    testWidgets(
      'real account connection applies pushes with offline recipe decision $decision',
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
        var savedEdits = 0;
        final held = <Map<String, dynamic>>[];
        Map<String, dynamic> library() {
          final data = snapshot(title);
          data['user']['id'] = '42';
          data['responses']['/households/1/meal-plan'] = {
            'revision': 1,
            'entries': [],
          };
          data['responses']['/households/1/meal-plan/history'] = {
            'entries': [],
          };
          data['responses']['/households/1/restaurants'] = {
            'revision': 1,
            'items': [],
          };
          data['recipes'].add({'id': '2', 'title': 'Other $title'});
          data['responses']['/households/1/recipes/2'] = {
            'recipe': {
              'id': '2',
              'title': 'Other $title',
              'category_assignments': [],
              'photos': [],
              'steps': [],
              'ingredients': [],
            },
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
                final household = m['scope'] == 'app';
                if (household) householdPeers.add(ws);
                ws.add(
                  jsonEncode({
                    'type': 'ready',
                    'household_id': null,
                    'data': household
                        ? {
                            'account': {
                              'user': {
                                'id': '42',
                                'display_name': 'Alice',
                                'child_mode': false,
                              },
                              'households': [
                                {'id': '1', 'name': 'Table', 'role': 'owner'},
                              ],
                              'people_child_modes': <String, dynamic>{},
                            },
                            'households': {'1': state()},
                          }
                        : {},
                  }),
                );
              } else if (m['type'] == 'request') {
                final path = m['path'] as String;
                if (path == '/households/1/recipes/1' && m['body'] is Map) {
                  savedEdits++;
                  if (decision == 'shared' &&
                      (m['body'] as Map)['confirm_shared_edit'] != true) {
                    ws.add(
                      jsonEncode({
                        'type': 'error',
                        'id': m['id'],
                        'status': 409,
                        'error': {
                          'code': 'shared_confirmation_required',
                          'message': 'Confirm changes to the shared recipe.',
                        },
                      }),
                    );
                    return;
                  }
                  title = (m['body'] as Map)['title'] as String;
                }
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
            const MethodChannel(
              'dev.fluttercommunity.plus/connectivity_status',
            ),
            null,
          );
          await directory.delete(recursive: true);
          connectedHouseholds.value = {};
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
          fail('Connection did not settle: ${connectedHouseholds.value}');
        }

        final store = OfflineFileStore(directory: () async => directory);
        final sqlite = LocalSqlite(
          factory: sqliteFactory,
          path: '${directory.path}/app.sqlite',
          readLegacy: store.read,
        );
        final offlineKey = 'offline-actions-$apiStorageNamespace|test-user';
        if (decision != null) {
          await tester.runAsync(
            () => store.write(
              offlineKey,
              jsonEncode([
                {
                  'id': 'offline-edit',
                  'kind': 'recipe',
                  'create': false,
                  'path': '/households/1/recipes/1',
                  'body': {'title': 'Offline soup'},
                },
              ]),
            ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: HouseholdPanel(
              user: SyncUser(),
              storage: sqlite,
              readPreference: (_) async => null,
              writePreference: (_, _) async {},
              socketConnect: (_) => WebSocketChannel.connect(
                Uri.parse('ws://127.0.0.1:${server.port}'),
              ),
            ),
          ),
        );
        try {
          await settleUntil(() => connectedHouseholds.value.contains('1'));
          expect(householdPeers, hasLength(1));
          if (decision != null) {
            await settleUntil(
              () =>
                  find.text('Save your offline changes?').evaluate().isNotEmpty,
            );
            expect(find.textContaining('Offline soup'), findsOneWidget);
            expect(
              find.textContaining('replace the recipe currently on the server'),
              findsOneWidget,
            );
          }
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
              'household_id': null,
              'data': {
                'households': {'1': state()},
              },
            }),
          );
          var received = false;
          for (var i = 0; i < 150; i++) {
            final state = await tester.runAsync(
              () =>
                  sqlite.read('local-first-v1-$apiStorageNamespace|test-user'),
            );
            if (state != null &&
                jsonDecode(
                      state,
                    )['data']['/households/1/recipes/2']?['recipe']?['title'] ==
                    'Other Remote recipe update') {
              received = true;
              break;
            }
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
          }
          expect(received, true);

          if (decision != null) {
            expect(find.text('Save your offline changes?'), findsOneWidget);
            expect(connectedHouseholds.value, contains('1'));
            await tester.tap(
              find.text(
                decision == 'save' || decision == 'shared'
                    ? 'Save to server'
                    : 'Discard my changes',
              ),
            );
            await settleUntil(
              () => find.text('Save your offline changes?').evaluate().isEmpty,
            );
            if (decision == 'shared') {
              await settleUntil(
                () =>
                    find.text('Save for all households').evaluate().isNotEmpty,
              );
              expect(connectedHouseholds.value, contains('1'));
              await tester.tap(find.text('Save for all households'));
              await settleUntil(
                () => find.text('Save for all households').evaluate().isEmpty,
              );
            }
            for (var i = 0; i < 30; i++) {
              final retained = await tester.runAsync(
                () => sqlite.read(
                  'local-first-v1-$apiStorageNamespace|test-user',
                ),
              );
              if (retained != null &&
                  (jsonDecode(retained)['pending'] as List).isEmpty) {
                break;
              }
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 20)),
              );
            }
            expect(
              await tester.runAsync(
                () => sqlite.read(
                  'local-first-v1-$apiStorageNamespace|test-user',
                ),
              ),
              predicate(
                (String text) => (jsonDecode(text)['pending'] as List).isEmpty,
              ),
            );
            expect(
              savedEdits,
              decision == 'shared'
                  ? 2
                  : decision == 'save'
                  ? 1
                  : 0,
            );
          }
          await tester.runAsync(() async {
            await householdPeers.last.close();
          });
          await settleUntil(() => !connectedHouseholds.value.contains('1'));
          await settleUntil(
            () =>
                householdPeers.length == 2 &&
                connectedHouseholds.value.contains('1'),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          });
          await tester.pump();
          await tester.runAsync(() => sqlite.close());
        }
      },
    );
  }
}
