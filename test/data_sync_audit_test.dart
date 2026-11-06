import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/shared_recipe_link.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/offline_store_io.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/shopping_socket.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class PeerServer {
  PeerServer(this.server);
  final HttpServer server;
  final peers = <WebSocket>[];
  static Future<PeerServer> start(void Function(WebSocket, Map) receive) async {
    final fixture = PeerServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      fixture.peers.add(ws);
      ws.listen((raw) => receive(ws, jsonDecode(raw as String) as Map));
    });
    return fixture;
  }

  Uri get uri => Uri.parse('ws://127.0.0.1:${server.port}');
  Future<void> close() async {
    for (final ws in peers) {
      unawaited(ws.close());
    }
    await server.close(force: true);
  }
}

void frame(WebSocket ws, Map data) => ws.add(jsonEncode(data));
String jwt(String uid, int expires) =>
    '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'fixture', 'aud': 'fixture', 'sub': uid, 'exp': expires})))}.signature';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'public shared-link client accepts the deployed empty-array handshake',
    () async {
      final server = await PeerServer.start((ws, data) {
        if (data['type'] == 'auth') {
          expect(data['scope'], 'public');
          expect(data['token'], '');
          frame(ws, {'type': 'ready', 'household_id': null, 'data': []});
        } else if (data['type'] == 'request') {
          frame(ws, {
            'type': 'response',
            'id': data['id'],
            'data': {
              'recipe': {'id': '9', 'title': 'Soup'},
            },
          });
        }
      });
      final api = RecipeApi(
        baseUrl: 'https://unused.test',
        socketConnect: (_) => WebSocketChannel.connect(server.uri),
      );
      addTearDown(() async {
        api.close();
        await server.close();
      });
      expect(
        (await api
            .request('/recipes/9', '')
            .timeout(const Duration(seconds: 3)))['recipe']['title'],
        'Soup',
      );
    },
  );

  test('malformed response fails its waiter immediately and reconnects autonomously', () async {
    var auths = 0, reads = 0;
    final recovered = Completer<void>();
    final server = await PeerServer.start((ws, data) {
      if (data['type'] == 'auth') {
        auths++;
        frame(ws, {'type': 'ready', 'household_id': null, 'data': {}});
        if (auths == 2 && !recovered.isCompleted) recovered.complete();
      } else if (data['type'] == 'request') {
        reads++;
        frame(ws, {
          'type': 'response',
          'id': data['id'],
          'data': reads == 1 ? [] : {'ok': true},
        });
      }
    });
    final socket = ShoppingSocket(
      household: '',
      scope: 'public',
      token: (_) async => '',
      onSnapshot: (_) async {},
      url: server.uri.toString(),
    );
    addTearDown(() async {
      socket.dispose();
      await server.close();
    });
    await expectLater(
      socket.request('/recipes/9').timeout(const Duration(seconds: 2)),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'invalid_server_message',
        ),
      ),
    );
    await recovered.future.timeout(const Duration(seconds: 3));
    expect(await socket.request('/recipes/9'), {'ok': true});
    expect(auths, 2);
  });

  test(
    'snapshot storage failure invalidates readiness and automatically retries',
    () async {
      var installs = 0;
      final ready = Completer<void>();
      final server = await PeerServer.start((ws, data) {
        if (data['type'] == 'auth') {
          frame(ws, {'type': 'ready', 'household_id': '1', 'data': {}});
        }
      });
      final socket = ShoppingSocket(
        household: '1',
        token: (_) async => 'alice',
        onSnapshot: (_) async {
          installs++;
          if (installs == 1) {
            throw FileSystemException('fixture storage failure');
          }
        },
        onReady: () {
          if (!ready.isCompleted) ready.complete();
        },
        url: server.uri.toString(),
      );
      addTearDown(() async {
        socket.dispose();
        await server.close();
      });
      socket.start();
      await ready.future.timeout(const Duration(seconds: 3));
      expect(installs, 2);
      expect(socket.connected, true);
    },
  );

  test(
    'ordinary missing recipe does not disconnect unrelated pending writes',
    () async {
      var auths = 0;
      final server = await PeerServer.start((ws, data) {
        if (data['type'] == 'auth') {
          auths++;
          frame(ws, {'type': 'ready', 'household_id': '1', 'data': {}});
        } else if ('${data['path']}'.endsWith('/999')) {
          frame(ws, {
            'type': 'error',
            'id': data['id'],
            'status': 404,
            'error': {'code': 'recipe_not_found', 'message': 'Missing recipe'},
          });
        } else {
          frame(ws, {
            'type': 'response',
            'id': data['id'],
            'data': {'revision': 2},
          });
        }
      });
      final socket = ShoppingSocket(
        household: '1',
        scope: 'household',
        token: (_) async => 'alice',
        onSnapshot: (_) async {},
        url: server.uri.toString(),
      );
      addTearDown(() async {
        socket.dispose();
        await server.close();
      });
      await expectLater(
        socket.request('/households/1/recipes/999'),
        throwsA(isA<ApiException>()),
      );
      expect(socket.connected, true);
      expect(
        await socket.request('/households/1/meal-plan', body: {'id': 'meal'}),
        {'revision': 2},
      );
      expect(auths, 1);
    },
  );

  test('token refresh preserves an in-flight write; account switch authenticates anew', () async {
    var auths = 0;
    final writing = Completer<void>(), release = Completer<void>();
    final server = await PeerServer.start((ws, data) async {
      if (data['type'] == 'auth') {
        auths++;
        frame(ws, {
          'type': 'ready',
          'household_id': data['household_id'],
          'data': {},
        });
      } else if (data['body'] != null) {
        writing.complete();
        await release.future;
        frame(ws, {
          'type': 'response',
          'id': data['id'],
          'data': {'saved': true},
        });
      } else {
        frame(ws, {
          'type': 'response',
          'id': data['id'],
          'data': {'ok': true},
        });
      }
    });
    final api = RecipeApi(
      baseUrl: 'https://unused.test',
      socketConnect: (_) => WebSocketChannel.connect(server.uri),
    );
    addTearDown(() async {
      api.close();
      await server.close();
    });
    final save = api.request(
      '/households/1/recipes/1',
      jwt('alice', 1),
      body: {'title': 'Soup'},
    );
    await writing.future;
    expect(await api.request('/me', jwt('alice', 2)), {'ok': true});
    release.complete();
    expect(await save, {'saved': true});
    expect(auths, 2); // household + account, no reopened household connection
    await api.request('/me', jwt('bob', 3));
    expect(auths, 3);
  });

  test(
    'simultaneous cache writes never collide on a shared temporary file',
    () async {
      final dir = await Directory.systemTemp.createTemp('ctr-audit-store-');
      addTearDown(() => dir.delete(recursive: true));
      final stores = List.generate(
        8,
        (_) => OfflineFileStore(directory: () async => dir),
      );
      await Future.wait([
        for (var i = 0; i < stores.length; i++)
          stores[i].write('shared', jsonEncode({'writer': i})),
      ]);
      expect(
        jsonDecode((await stores.first.read('shared'))!),
        contains('writer'),
      );
    },
  );

  testWidgets(
    'a failed recipe read retries itself and recovers without a tap',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '0',
            recipeId: '9',
            title: 'Shared recipe',
            request: (_) async {
              attempts++;
              if (attempts == 1) throw ApiException(503, 'Data sync paused');
              return {
                'recipe': {'id': '9', 'title': 'Recovered soup'},
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Data sync paused'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Recovered soup'), findsOneWidget);
      expect(attempts, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('a missing reply does not interrupt a healthy transport', () async {
    var auths = 0, requests = 0;
    final server = await PeerServer.start((ws, data) {
      if (data['type'] == 'auth') {
        auths++;
        frame(ws, {'type': 'ready', 'household_id': null, 'data': {}});
      } else if (data['type'] == 'ping') {
        frame(ws, {'type': 'pong'});
      } else if (data['type'] == 'request' && ++requests > 1) {
        frame(ws, {
          'type': 'response',
          'id': data['id'],
          'data': {'ok': true},
        });
      }
    });
    final socket = ShoppingSocket(
      household: '',
      scope: 'public',
      token: (_) async => '',
      onSnapshot: (_) async {},
      url: server.uri.toString(),
    );
    addTearDown(() async {
      socket.dispose();
      await server.close();
    });
    await expectLater(
      socket.request('/recipes/9', timeout: const Duration(milliseconds: 100)),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'response_timeout'),
      ),
    );
    expect(socket.connected, true);
    expect(auths, 1);
    expect(await socket.request('/recipes/9'), {'ok': true});
  });

  testWidgets('shared recipe route renders through its real public adapter', (
    tester,
  ) async {
    final paths = <String>[];
    final api = RecipeApi(
      baseUrl: 'https://fixture.test',
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          jsonEncode({
            'recipe': {
              'id': '9',
              'title': 'Public soup',
              'description': 'Shared directions',
            },
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SharedRecipeLink(recipeId: '9', api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Shared directions'),
      findsOneWidget,
      reason:
          'paths=$paths texts=${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}',
    );
    expect(paths, contains('/recipes/9'));
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'public recipe recovery is independent of the household offline flag',
    () async {
      var calls = 0;
      final cache = OfflineRecipes(
        key: 'public-independent',
        read: (_) async => null,
        write: (_, _) async {},
        fetch: (_) async {
          calls++;
          return {
            'recipe': {'id': '9', 'title': 'Public soup'},
          };
        },
      );
      addTearDown(() {
        cache.close();
        offlineStatus.value = false;
      });
      offlineStatus.value = true;
      expect(
        (await cache.request('/recipes/9'))['recipe']['title'],
        'Public soup',
      );
      expect(calls, 1);
      expect(
        offlineStatus.value,
        true,
        reason: 'A public read must not change private sync state',
      );
    },
  );

  testWidgets(
    'hung optional cache storage cannot prevent a public online read',
    (tester) async {
      final read = Completer<String?>(), write = Completer<void>();
      final cache = OfflineRecipes(
        key: 'hung-cache',
        read: (_) => read.future,
        write: (_, _) => write.future,
        fetch: (_) async => {
          'recipe': {'id': '9', 'title': 'Online soup'},
        },
      );
      addTearDown(cache.close);
      Map<String, dynamic>? loaded;
      cache.request('/recipes/9').then((value) => loaded = value);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(loaded?['recipe']['title'], 'Online soup');
    },
  );
}
