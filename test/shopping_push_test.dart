import 'dart:convert';
import 'dart:async';

import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const path = '/households/1/shopping-list';
  Map<String, dynamic> item(String id) => {
    'id': id,
    'name': id,
    'checked': false,
    'department': '',
  };
  Map<String, dynamic> state(int revision, List<Map<String, dynamic>> items) =>
      {
        'revision': revision,
        'items': items,
        'departments': ['Other'],
      };
  test(
    'shopping can synchronize while the recipe HTTP transport is offline',
    () async {
      final sent = <String>[];
      final data = LocalData(
        key: 'independent-transports',
        fetch: (_) async => {},
        send: (path, body) async {
          sent.add(path);
          return {
            ...state(2, []),
            'acknowledged_change_id': body['client_change_id'],
          };
        },
        online: () => false,
        canSend: (resource) => resource == path,
        separateShopping: true,
        readStore: (_) async => null,
        writeStore: (_, _) async {},
      );
      addTearDown(data.dispose);
      await data.acceptShopping('1', state(1, [item('milk')]));
      await data.save(path, {'revision': 1, 'items': []});
      await data.synchronize();
      expect(sent, [path]);
      expect(data.pending, 0);
    },
  );
  test(
    'a delayed acknowledgement cannot roll back a newer committed push',
    () async {
      final entered = Completer<Map<String, dynamic>>();
      final response = Completer<Map<String, dynamic>>();
      final data = LocalData(
        key: 'ack-race',
        fetch: (_) async => {},
        send: (_, body) {
          entered.complete(body);
          return response.future;
        },
        separateShopping: true,
        readStore: (_) async => null,
        writeStore: (_, _) async {},
      );
      addTearDown(data.dispose);
      await data.acceptShopping('1', state(1, [item('milk')]));
      await data.save(path, {
        'revision': 1,
        'items': [
          {...item('milk'), 'checked': true},
        ],
      });
      final body = await entered.future;
      await data.acceptShopping(
        '1',
        state(3, [
          {...item('milk'), 'checked': true},
          item('bread'),
        ]),
      );
      response.complete({
        ...state(2, [
          {...item('milk'), 'checked': true},
        ]),
        'acknowledged_change_id': body['client_change_id'],
      });
      await data.synchronize();
      expect((data.readView(path)['items'] as List).map((i) => i['id']), [
        'milk',
        'bread',
      ]);
      expect(data.readView(path)['revision'], 3);
      expect(data.pending, 0);
    },
  );
  test('pushes preserve pending deletions, survive restart and reject older revisions', () async {
    final disk = <String, String>{};
    LocalData create() => LocalData(
      key: 'push',
      fetch: (_) async => {},
      send: (_, _) async => {},
      online: () => false,
      separateShopping: true,
      snapshotOnly: true,
      readStore: (k) async => disk[k],
      writeStore: (k, v) async {
        disk[k] = v;
      },
    );
    var data = create();
    await data.acceptShopping('1', state(1, [item('milk')]));
    await data.save(path, {'revision': 1, 'items': []});
    await data.acceptShopping('1', state(2, [item('milk'), item('bread')]));
    expect((data.readView(path)['items'] as List).map((i) => i['id']), [
      'bread',
    ]);
    expect(data.pending, 1);
    data.dispose();
    data = create();
    await data.acceptShopping('1', state(1, [item('milk')]));
    expect((await data.request(path))['items'], [item('bread')]);
    expect(data.pending, 1);
    expect(jsonEncode(disk), contains('client_change_id'));
    data.dispose();
  });

  test(
    'legacy household snapshots cannot replace or remove VPS shopping',
    () async {
      final data = LocalData(
        key: 'snapshot',
        fetch: (_) async => {},
        send: (_, _) async => {},
        separateShopping: true,
        snapshotOnly: true,
        readStore: (_) async => null,
        writeStore: (_, _) async {},
      );
      addTearDown(data.dispose);
      await data.acceptShopping('1', state(4, [item('fresh')]));
      for (final legacy in [true, false]) {
        await data.installSnapshot({
          'schema': 1,
          'household_id': '1',
          'version': '$legacy',
          'recipes': [],
          'categories': [],
          'edit_options': {},
          'responses': {
            '/households/1/people': {'people': []},
            '/households/1/recipe-blank': {'recipe': {}},
            if (legacy) path: state(1, [item('stale')]),
          },
        });
        expect(data.readView(path)['items'], [item('fresh')]);
      }
    },
  );
}
