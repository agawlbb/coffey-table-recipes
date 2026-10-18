import 'dart:async';

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
  testWidgets(
    'all departments are drop targets and a drag changes department',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var items = [item('Apples')];
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
      for (final department in shoppingDepartments) {
        expect(find.byKey(ValueKey('department-$department')), findsOneWidget);
      }
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      final destination = tester.getRect(
        find.byKey(const ValueKey('empty-Dairy & eggs')),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Apples')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(destination.center);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(items.single['department'], 'Dairy & eggs');
      expect(
        tester.getTopLeft(find.text('Apples')).dy,
        greaterThan(tester.getTopLeft(find.text('Dairy & eggs')).dy),
      );
      for (final department in ['Meat & seafood', 'Bakery', 'Produce']) {
        final target = tester.getCenter(
          find.byKey(ValueKey('empty-$department')),
        );
        final nextDrag = await tester.startGesture(
          tester.getCenter(find.text('Apples')),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await nextDrag.moveTo(target);
        await tester.pump(const Duration(milliseconds: 300));
        await nextDrag.moveBy(const Offset(0, 2));
        await tester.pump(const Duration(milliseconds: 300));
        await nextDrag.up();
        await tester.pumpAndSettle();
        expect(items.single['department'], department);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'consecutive drags survive delayed saves and changing empty sections',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var items = [
        item('Apples'),
        {...item('Milk'), 'department': 'Dairy & eggs'},
      ];
      var revision = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: ShoppingListScreen(
            householdId: '1',
            householdName: 'Our table',
            request: (path, {body}) async {
              if (body != null) {
                await Future<void>.delayed(const Duration(milliseconds: 600));
                revision++;
                items = List<Map<String, dynamic>>.from(body['items'] as List);
              }
              return {'revision': revision, 'items': items};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final department in [
        'Dairy & eggs',
        'Produce',
        'Dairy & eggs',
        'Meat & seafood',
      ]) {
        final empty = find.byKey(ValueKey('empty-$department'));
        final target = empty.evaluate().isNotEmpty
            ? tester.getCenter(empty)
            : tester.getCenter(find.text('Milk'));
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Apples')),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveTo(target);
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.moveBy(const Offset(0, 2));
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          items.firstWhere((item) => item['id'] == 'Apples')['department'],
          department,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('another drag queues while the first save is pending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final firstSave = Completer<void>();
    final writes = <Map<String, dynamic>>[];
    var saved = [item('Apples')];
    var revision = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '1',
          householdName: 'Our table',
          request: (path, {body}) async {
            if (body != null) {
              writes.add(body);
              expect(body['revision'], revision);
              if (writes.length == 1) await firstSave.future;
              revision++;
              saved = List<Map<String, dynamic>>.from(body['items'] as List);
            }
            return {'revision': revision, 'items': saved};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final department in ['Dairy & eggs', 'Meat & seafood']) {
      final target = tester.getCenter(
        find.byKey(ValueKey('empty-$department')),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Apples')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(target);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester.getTopLeft(find.text('Apples')).dy,
        greaterThan(tester.getTopLeft(find.text(department)).dy),
        reason: 'Pending-save drop into $department',
      );
    }
    expect(writes, hasLength(1));
    firstSave.complete();
    await tester.pumpAndSettle();
    expect(writes, hasLength(2));
    expect(saved.single['department'], 'Meat & seafood');
    expect(revision, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
      'Bananas',
      'Carrots',
      'Apples',
      'Milk',
    ]);
    expect(items.last['department'], 'Dairy & eggs');
    expect(
      items.take(3).every((item) => item['department'] == 'Produce'),
      isTrue,
    );
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
