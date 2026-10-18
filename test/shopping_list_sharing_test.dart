import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> item(String name) => {
  'id': name,
  'name': name,
  'checked': false,
  'department': 'Produce',
};

void main() {
  testWidgets('holding a row reorders the persisted list', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var items = [
      {...item('Milk'), 'department': 'Dairy & eggs'},
      item('Apples'),
      item('Bananas'),
      item('Carrots'),
    ];
    var revision = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '1',
          householdName: 'Our table',
          request: (path, {body}) async {
            if (body != null) {
              revision++;
              items = List<Map<String, dynamic>>.from(body['items'] as List);
            }
            return {'revision': revision, 'items': items};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Produce'), findsOneWidget);
    expect(find.text('Dairy & eggs'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Produce')).dy,
      lessThan(tester.getTopLeft(find.text('Apples')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Carrots')).dy,
      lessThan(tester.getTopLeft(find.text('Dairy & eggs')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Dairy & eggs')).dy,
      lessThan(tester.getTopLeft(find.text('Milk')).dy),
    );
    final from = tester.getCenter(find.text('Apples'));
    final to = tester.getCenter(find.text('Carrots'));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(to + const Offset(0, 55));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(items.map((i) => i['name']), [
      'Milk',
      'Bananas',
      'Carrots',
      'Apples',
    ]);
    expect(items.first['department'], 'Dairy & eggs');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale writes reload shared items and preserve the add field', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '1',
          householdName: 'Our table',
          request: (path, {body}) async {
            if (body != null) {
              throw ApiException(409, 'The shopping list changed. Try again.');
            }
            reads++;
            return {
              'revision': reads,
              'items': [item(reads == 1 ? 'Apples' : 'Pears')],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Milk');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Pears'), findsOneWidget);
    expect(find.text('The shopping list changed. Try again.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Milk',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
