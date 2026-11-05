// Run with CTR_BACKEND_SOURCE pointing to the matching VPS checkout, in the
// shared dev container. This exercises production Dart and PHP transport code
// together using an isolated SQLite database, never the hosted database.
import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Platform.environment['CTR_BACKEND_SOURCE'];
  test(
    'real PHP server and Dart client agree on public, household and timer contracts',
    () async {
      final root = Directory(source!);
      final temporary = await Directory.systemTemp.createTemp('ctr-dart-php-');
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final media = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final mediaPort = media.port;
      await media.close();
      final process = await Process.start(
        'setsid',
        [
          'php',
          File('${root.path}/tests/fixtures/client_contract_server.php')
                  .existsSync()
              ? 'tests/fixtures/client_contract_server.php'
              : 'tests/fixtures/data_socket_server.php',
          'start',
        ],
        workingDirectory: root.path,
        environment: {
          ...Platform.environment,
          'CTR_LISTEN': 'websocket://127.0.0.1:$port',
          'CTR_MEDIA_LISTEN': 'http://127.0.0.1:$mediaPort',
          'CTR_TEST_DATABASE': '${temporary.path}/data.sqlite',
          'CTR_RUNTIME_DIR': temporary.path,
          'CTR_STORAGE': '${temporary.path}/state',
        },
      );
      final logs = StringBuffer();
      process.stdout.transform(utf8.decoder).listen(logs.write);
      process.stderr.transform(utf8.decoder).listen(logs.write);
      final api = RecipeApi(
        baseUrl: 'https://unused.test',
        socketConnect: (_) =>
            WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port')),
      );
      addTearDown(() async {
        api.close();
        await Process.run('kill', ['-TERM', '--', '-${process.pid}']);
        await process.exitCode.timeout(const Duration(seconds: 5));
        await temporary.delete(recursive: true);
      });
      for (var attempt = 0; attempt < 100; attempt++) {
        try {
          final socket = await Socket.connect('127.0.0.1', port);
          socket.destroy();
          break;
        } catch (_) {
          if (attempt == 99) fail('PHP fixture did not start: $logs');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      final raw = await WebSocket.connect('ws://127.0.0.1:$port');
      raw.add(
        jsonEncode({
          'v': 1,
          'type': 'auth',
          'scope': 'public',
          'token': '',
          'household_id': null,
        }),
      );
      final ready = jsonDecode(await raw.first as String) as Map;
      expect(
        ready['data'],
        isA<Map>(),
        reason: 'The actual client requires a JSON object, not []',
      );
      await raw.close();
      final public = await api
          .request('/recipes/1', '')
          .timeout(const Duration(seconds: 5));
      expect(public['recipe']['title'], 'Soup');
      if (File('${root.path}/tests/fixtures/client_contract_server.php')
          .existsSync()) {
        expect(
          logs.toString(),
          contains('CTR socket failure RuntimeException'),
        );
        expect(
          logs.toString(),
          isNot(contains('private-fixture-marker-must-not-leak')),
        );
      }
      await expectLater(
        api.request('/recipes/999999', ''),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
      expect((await api.request('/recipes/1', ''))['recipe']['title'], 'Soup');
      final local = LocalData(
        key: 'cross-language',
        snapshotOnly: true,
        separateShopping: true,
        fetch: (path) => api.request(path, 'alice'),
        send: (path, body) => api.request(path, 'alice', body: body),
        readStore: (_) async => null,
        writeStore: (_, _) async {},
      );
      addTearDown(local.dispose);
      final snapshot = await api.request('/households/1/snapshot', 'alice');
      final shopping = await api.request(
        '/households/1/shopping-list',
        'alice',
      );
      await local.acceptShopping('1', shopping);
      await local.installSnapshot(snapshot);
      expect(local.isHouseholdConfirmed('1'), true);
      final plan = await local.request(
        '/households/1/meal-plan?from=2000-01-01&to=2199-12-31',
      );
      await local.save('/households/1/meal-plan', {
        'revision': plan['revision'],
        'id': 'contract-meal',
        'operation': 'add',
        'kind': 'leftovers',
        'date': '2099-11-05',
        'confirm_past': false,
      });
      expect(local.isHouseholdConfirmed('1'), false);
      await Future<void>.delayed(Duration.zero);
      await local.synchronize();
      expect(local.pending, 0);
      expect(
        local.isHouseholdConfirmed('1'),
        false,
        reason: 'An acknowledgment is not full replica confirmation',
      );
      final after = await api.request('/households/1/snapshot', 'alice');
      await local.acceptShopping(
        '1',
        await api.request('/households/1/shopping-list', 'alice'),
      );
      await local.installSnapshot(after);
      expect(local.isHouseholdConfirmed('1'), true);
      expect(
        local.readView('/households/1/meal-plan')['entries'],
        (after['responses'] as Map)['/households/1/meal-plan']['entries'],
      );
      expect((await api.request('/me/timers', 'alice'))['timers'], isA<List>());
      expect((await api.request('/recipes/1', ''))['recipe']['title'], 'Soup');
    },
    skip: source == null
        ? 'Set CTR_BACKEND_SOURCE to run the real PHP/Dart contract check'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
