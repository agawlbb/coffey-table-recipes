import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a push received during inline editing appears when editing ends without a save',
    (tester) async {
      var name = 'Milk', writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ShoppingListScreen(
            householdId: '1',
            householdName: 'Table',
            localFirst: true,
            request: (path, {body}) async {
              if (body != null) writes++;
              return {
                'revision': 0,
                'departments': ['Dairy'],
                'items': [
                  {
                    'id': 'milk',
                    'name': name,
                    'department': 'Dairy',
                    'checked': false,
                  },
                ],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == 'Milk',
        ),
        findsOneWidget,
      );
      name = 'Server milk';
      localDataChanges.value = '/households/1/shopping-list#remote';
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('Server milk'), findsOneWidget);
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
