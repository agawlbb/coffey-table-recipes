import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/offline_changes.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'check and remove offline retains specific removals without replacing later server items',
    (tester) async {
      offlineStatus.value = true;
      addTearDown(() => offlineStatus.value = false);
      final disk = <String, String>{};
      final pending = OfflineChanges(
        account: 'alice',
        read: (key) async => disk[key],
        write: (key, text) async {
          disk[key] = text;
        },
      );
      var items = <Map<String, dynamic>>[
        {'id': 'milk', 'name': 'Milk', 'checked': false, 'department': 'Dairy'},
        {
          'id': 'bread',
          'name': 'Bread',
          'checked': false,
          'department': 'Dairy',
        },
      ];
      var serverWrites = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ShoppingListScreen(
            householdId: '1',
            householdName: 'Table',
            localFirst: true,
            request: (path, {body}) async {
              if (body != null) {
                expect(body.keys, ['remove_ids']);
                await pending.removeItems(
                  path,
                  (body['remove_ids'] as List).cast<String>(),
                );
              }
              return pending.shopping(path, {
                'revision': 0,
                'departments': ['Dairy'],
                'items': items,
              });
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Remove checked off'));
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsNothing);
      expect(find.text('Bread'), findsOneWidget);
      expect(items, hasLength(2));
      expect(pending.hasAutomatic, true);
      items.add({
        'id': 'new-milk',
        'name': 'Milk again',
        'checked': false,
        'department': 'Dairy',
      });
      offlineStatus.value = false;
      await pending.sendAutomatic((path, body) async {
        serverWrites++;
        items = items
            .where((item) => !(body['remove_ids'] as List).contains(item['id']))
            .toList();
        return {};
      }, () => true);
      localDataChanges.value = '/households/1/shopping-list#uploaded';
      await tester.pumpAndSettle();
      expect(serverWrites, 1);
      expect(find.text('Milk again'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
      expect(pending.hasAutomatic, false);
      await tester.pumpWidget(const SizedBox());
      pending.dispose();
    },
  );
}
