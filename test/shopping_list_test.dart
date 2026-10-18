import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';

void main() {
  testWidgets('adds, checks, edits departments, and removes household items', (
    tester,
  ) async {
    var revision = 0;
    var items = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '7',
          householdName: 'Our table',
          request: (path, {body}) async {
            expect(path, '/households/7/shopping-list');
            if (body != null) {
              expect(body['revision'], revision);
              revision++;
              items = List<Map<String, dynamic>>.from(body['items'] as List);
            }
            return {'revision': revision, 'items': items};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Our table'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Milk');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('Milk'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
    expect(items.single['checked'], true);
    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dairy & eggs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(items.single['department'], 'Dairy & eggs');
    await tester.tap(find.text('Remove checked off'));
    await tester.pumpAndSettle();
    expect(items, isEmpty);
    expect(find.text('Your list is empty'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
