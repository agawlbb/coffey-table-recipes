import 'dart:ui' show PointerDeviceKind;
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
        find.byKey(const ValueKey('department-Dairy & eggs')),
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
          find.byKey(ValueKey('department-$department')),
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
        final target = tester.getCenter(
          find.byKey(ValueKey('department-$department')),
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
        find.byKey(ValueKey('department-$department')),
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

  testWidgets(
    'mouse and touch drags start across the label and row whitespace',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var saved = [item('A long shopping item label')];
      var revision = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ShoppingListScreen(
            householdId: '1',
            householdName: 'Our table',
            request: (path, {body}) async {
              if (body != null) {
                revision++;
                saved = List<Map<String, dynamic>>.from(body['items'] as List);
              }
              return {'revision': revision, 'items': saved};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 3; attempt++) {
        final label = tester.getRect(find.text('A long shopping item label'));
        final row = tester.getRect(
          find.byKey(const ValueKey('A long shopping item label')),
        );
        final from = attempt == 0
            ? Offset(label.left + 2, label.center.dy)
            : attempt == 1
            ? Offset(label.right - 2, label.center.dy)
            : Offset(row.right - 12, row.center.dy);
        final department = ['Dairy & eggs', 'Produce', 'Bakery'][attempt];
        final target = tester.getCenter(
          find.byKey(ValueKey('department-$department')),
        );
        final gesture = await tester.startGesture(
          from,
          kind: attempt == 1
              ? PointerDeviceKind.touch
              : PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveTo(target);
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(saved.single['department'], department);
        expect(saved.single['checked'], false);
      }
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        list.childrenDelegate.estimatedChildCount,
        shoppingDepartments.length + 1,
      );
      for (final department in shoppingDepartments) {
        expect(find.byKey(ValueKey('empty-$department')), findsNothing);
        expect(
          tester.getSize(find.byKey(ValueKey('department-$department'))).height,
          30,
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('dragging at the list edge scrolls to offscreen departments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '1',
          householdName: 'Our table',
          request: (path, {body}) async => {
            'revision': 0,
            'items': [for (var i = 0; i < 20; i++) item('Item $i')],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final bounds = tester.getRect(find.byType(ListView));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Item 0')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(Offset(bounds.center.dx, bounds.bottom - 5));
    await tester.pump(const Duration(seconds: 1));
    expect(list.controller!.offset, greaterThan(0));
    await gesture.cancel();
    await tester.pumpAndSettle();
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
    await gesture.moveTo(to + const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, 2));
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
    expect(
      items.skip(1).every((item) => item['department'] == 'Produce'),
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
