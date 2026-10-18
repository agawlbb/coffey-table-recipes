import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'requests synchronization once per opening, not polls or rebuilds',
    (tester) async {
      var active = true;
      var requests = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ShoppingListScreen(
                householdId: '1',
                householdName: 'Family',
                active: active,
                request: (path, {body}) async => {'revision': 0, 'items': []},
                requestSynchronization: () async {
                  requests++;
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      update(() {});
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 15));
      expect(requests, 1);
      update(() {
        active = false;
      });
      await tester.pumpAndSettle();
      update(() {
        active = true;
      });
      await tester.pumpAndSettle();
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('sync failure does not hide or block the shopping list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '1',
          householdName: 'Family',
          request: (path, {body}) async => {
            'revision': 1,
            'items': [
              {
                'id': 'milk',
                'name': 'Milk',
                'checked': false,
                'department': '',
              },
            ],
          },
          requestSynchronization: () async {
            throw Exception('Offline');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
