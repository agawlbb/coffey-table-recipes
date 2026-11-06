import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/offline_changes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> disk;
  late DateTime now;
  OfflineChanges create([String account = 'server|alice']) => OfflineChanges(
    account: account,
    read: (key) async => disk[key],
    write: (key, text) async {
      disk[key] = text;
    },
    now: () => now,
  );
  setUp(() {
    disk = {};
    now = DateTime.utc(2026, 11, 6);
  });
  Future<Map<String, dynamic>> unavailable(
    String path,
    Map<String, dynamic> body,
  ) async => throw ApiException(503, 'Unavailable');

  test('new recipes survive restart, automatically upload, and reuse the original receipt after a lost reply', () async {
    final first = create();
    final retained = await first.saveRecipe(
      '/households/1/recipes',
      {'title': 'Soup'},
      connected: false,
      send: unavailable,
    );
    expect(retained['_offline_pending'], true);
    final restarted = create();
    await restarted.load();
    final ids = <String>[];
    await restarted.sendAutomatic((path, body) async {
      ids.add(body['client_save_id'] as String);
      throw ApiException(503, 'Lost response');
    }, () => true);
    expect(restarted.recipes, hasLength(1));
    await restarted.sendAutomatic((path, body) async {
      ids.add(body['client_save_id'] as String);
      return {
        'recipe': {'id': '9'},
      };
    }, () => true);
    expect(ids.toSet(), hasLength(1));
    expect(restarted.recipes, isEmpty);
  });
  test('edits never automatically submit and do not block unrelated additions or removals', () async {
    final changes = create();
    await changes.saveRecipe(
      '/households/1/recipes/1',
      {'title': 'Edit', 'revision': 'old'},
      connected: false,
      send: unavailable,
    );
    await changes.saveRecipe(
      '/households/1/recipes',
      {'title': 'New'},
      connected: false,
      send: unavailable,
    );
    await changes.removeItems('/households/1/shopping-list', ['milk']);
    final sent = <String>[];
    await changes.sendAutomatic((path, body) async {
      sent.add(path);
      return {};
    }, () => true);
    expect(sent, ['/households/1/recipes', '/households/1/shopping-list']);
    final edit = changes.recipes.single;
    expect(edit['body'], isNot(contains('revision')));
    await changes.submit(edit, (path, body) async {
      sent.add(path);
      return {};
    });
    expect(sent.last, '/households/1/recipes/1');
    expect(changes.recipes, isEmpty);
  });
  test(
    'discarding an offline edit never sends or deletes server data',
    () async {
      final changes = create();
      await changes.saveRecipe(
        '/households/1/recipes/1',
        {'title': 'Edit'},
        connected: false,
        send: unavailable,
      );
      await changes.discard(changes.recipes.single['id'] as String);
      final restarted = create();
      await restarted.load();
      expect(restarted.recipes, isEmpty);
    },
  );
  test('shopping deletion targets an identity, survives restart and expires exactly at two hours', () async {
    const path = '/households/1/shopping-list';
    final changes = create();
    await changes.removeItems(path, ['old-milk']);
    final restarted = create();
    await restarted.load();
    final server = {
      'items': [
        {'id': 'old-milk', 'name': 'Milk'},
        {'id': 'new-milk', 'name': 'Milk'},
      ],
    };
    expect(restarted.shopping(path, server)['items'], [
      {'id': 'new-milk', 'name': 'Milk'},
    ]);
    now = now.add(const Duration(hours: 2));
    final sent = <String>[];
    await restarted.sendAutomatic((path, body) async {
      sent.add(path);
      return {};
    }, () => true);
    expect(sent, isEmpty);
    expect(restarted.shopping(path, server)['items'], server['items']);
  });
  test('a failed automatic action cannot hold other actions or a separate server request', () async {
    final changes = create();
    await changes.saveRecipe(
      '/households/1/recipes',
      {'title': 'One'},
      connected: false,
      send: unavailable,
    );
    await changes.removeItems('/households/1/shopping-list', ['milk']);
    var removed = false;
    await changes.sendAutomatic((path, body) async {
      if (path.endsWith('/recipes')) throw ApiException(422, 'Invalid recipe');
      removed = true;
      return {};
    }, () => true);
    expect(removed, true);
    expect(changes.recipes, hasLength(1));
  });
  test(
    'device storage failure never acknowledges or hides an offline action',
    () async {
      var broken = false;
      final changes = OfflineChanges(
        account: 'alice',
        read: (key) async => disk[key],
        write: (key, value) async {
          if (broken) throw StateError('disk');
          disk[key] = value;
        },
      );
      await changes.saveRecipe(
        '/households/1/recipes/1',
        {'title': 'Edit'},
        connected: false,
        send: unavailable,
      );
      broken = true;
      await expectLater(
        changes.discard(changes.recipes.single['id'] as String),
        throwsA(isA<ApiException>()),
      );
      expect(changes.recipes, hasLength(1));
      await expectLater(
        changes.removeItems('/households/1/shopping-list', ['milk']),
        throwsA(isA<ApiException>()),
      );
      expect(
        changes.shopping('/households/1/shopping-list', {
          'items': [
            {'id': 'milk'},
          ],
        })['items'],
        hasLength(1),
      );
    },
  );
  test('queued work is scoped to account and backend and ordinary validation errors are not queued', () async {
    final changes = create();
    await changes.saveRecipe(
      '/households/1/recipes',
      {'title': 'One'},
      connected: false,
      send: unavailable,
    );
    final other = create('server|bob');
    await other.load();
    expect(other.recipes, isEmpty);
    await expectLater(
      changes.saveRecipe(
        '/households/1/recipes/2',
        {'title': ''},
        connected: true,
        send: (_, _) async => throw ApiException(422, 'Invalid recipe'),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(changes.recipes, hasLength(1));
  });
}
