import 'package:coffey_table_recipes/src/local_data.dart';
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
      var online = false;
      late LocalData pending;
      pending = LocalData(
        key: 'alice',
        fetch: (_) async => {},
        readStore: (key) async => disk[key],
        writeStore: (key, text) async {
          disk[key] = text;
        },
        send: (path, body) async {
          serverWrites++;
          for (final item in body['upsert_items'] as List? ?? []) {
            items.removeWhere((old) => old['id'] == item['id']);
            items.add(Map<String, dynamic>.from(item as Map));
          }
          items.removeWhere(
            (item) => (body['remove_ids'] as List? ?? []).contains(item['id']),
          );
          await pending.acceptShopping('1', {
            'revision': 0,
            'departments': ['Dairy'],
            'items': items,
          });
          return {};
        },
      )..connected = () => online;
      await pending.acceptShopping('1', {
        'revision': 0,
        'departments': ['Dairy'],
        'items': items,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ShoppingListScreen(
            householdId: '1',
            householdName: 'Table',
            localFirst: true,
            request: (path, {body}) async {
              if (body != null) return pending.save(path, body);
              return pending.request(path);
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
      online = true;
      await pending.synchronize();
      localDataChanges.value = '/households/1/shopping-list#uploaded';
      await tester.pumpAndSettle();
      expect(serverWrites, 2);
      expect(find.text('Milk again'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
      expect(pending.hasAutomatic, false);
      await tester.pumpWidget(const SizedBox());
      pending.dispose();
    },
  );
}
