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
    'legacy household snapshots cannot replace or remove VPS shopping',
    () async {
      final data = LocalData(
        key: 'snapshot',
        fetch: (_) async => {},
        send: (_, _) async => {},
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
