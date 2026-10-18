import 'dart:ui' show PointerDeviceKind;

import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a moved row retains its drag state and visible mouse cursor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var items = <Map<String, dynamic>>[
      {
        'id': 'apples',
        'name': 'Apples',
        'department': 'Produce',
        'checked': false,
      },
      {
        'id': 'milk',
        'name': 'Milk',
        'department': 'Dairy & eggs',
        'checked': false,
      },
      {
        'id': 'bread',
        'name': 'Bread',
        'department': 'Bakery',
        'checked': false,
      },
    ];
    var revision = 0;
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
    final draggable = find.descendant(
      of: find.byKey(const ValueKey('apples')),
      matching: find.byType(LongPressDraggable<String>),
    );
    final originalState = tester.state(draggable);
    for (final department in ['Bakery', 'Dairy & eggs', 'Produce']) {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(find.text('Apples')));
      await tester.pump();
      await gesture.down(tester.getCenter(find.text('Apples')));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(find.byKey(ValueKey('department-$department'))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        items.firstWhere((i) => i['id'] == 'apples')['department'],
        department,
      );
      expect(tester.state(draggable), same(originalState));
      await gesture.moveTo(tester.getCenter(find.text('Apples')));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      await gesture.removePointer();
    }
    await tester.pumpWidget(const SizedBox());
  });
}
