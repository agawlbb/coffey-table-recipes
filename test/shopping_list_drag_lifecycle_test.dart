import 'dart:ui' show PointerDeviceKind;

import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'new unassigned items stay above departments and empty sections can be hidden',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var items = <Map<String, dynamic>>[
        {
          'id': 'milk',
          'name': 'Milk',
          'department': 'Dairy & eggs',
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
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(find.byType(TextField), 'Apples');
      await tester.tap(find.byTooltip('Add item'));
      await tester.pumpAndSettle();
      expect(items.firstWhere((i) => i['name'] == 'Apples')['department'], '');
      expect(
        tester.getBottomLeft(find.text('Apples')).dy,
        lessThan(tester.getTopLeft(find.text('Dairy & eggs')).dy),
      );
      final assign = await tester.startGesture(
        tester.getCenter(find.text('Apples')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await assign.moveTo(
        tester.getCenter(find.byKey(const ValueKey('department-Produce'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await assign.up();
      await tester.pumpAndSettle();
      expect(
        items.firstWhere((i) => i['name'] == 'Apples')['department'],
        'Produce',
      );
      expect(find.byKey(const ValueKey('department-Bakery')), findsNothing);
      expect(find.byKey(const ValueKey('department-Produce')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('department-Dairy & eggs')),
        findsOneWidget,
      );
      final unassign = await tester.startGesture(
        tester.getCenter(find.text('Apples')),
        kind: PointerDeviceKind.mouse,
      );
      await unassign.moveTo(
        tester.getCenter(find.byKey(const ValueKey('department-'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await unassign.up();
      await tester.pumpAndSettle();
      expect(items.firstWhere((i) => i['name'] == 'Apples')['department'], '');
      expect(find.byKey(const ValueKey('department-Produce')), findsNothing);
      expect(
        tester.getBottomLeft(find.text('Apples')).dy,
        lessThan(tester.getTopLeft(find.text('Dairy & eggs')).dy),
      );
      expect(
        items.firstWhere((i) => i['id'] == 'milk')['department'],
        'Dairy & eggs',
      );
      expect(find.text('Hide empty departments'), findsNothing);
      expect(find.byKey(const ValueKey('department-Produce')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mouse dragging starts without a long-press delay', (
    tester,
  ) async {
    var items = <Map<String, dynamic>>[
      {
        'id': 'apples',
        'name': 'Apples',
        'department': 'Produce',
        'checked': false,
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '1',
          householdName: 'Our table',
          request: (path, {body}) async {
            if (body != null) {
              items = List<Map<String, dynamic>>.from(body['items'] as List);
            }
            return {'revision': body == null ? 0 : 1, 'items': items};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Apples')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('department-Dairy & eggs'))),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(items.single['department'], 'Dairy & eggs');
    expect(items.single['checked'], false);
    final touch = await tester.startGesture(
      tester.getCenter(find.text('Apples')),
      kind: PointerDeviceKind.touch,
    );
    await touch.moveBy(const Offset(0, -50));
    await tester.pump(const Duration(milliseconds: 50));
    await touch.up();
    await tester.pumpAndSettle();
    expect(items.single['department'], 'Dairy & eggs');
    final click = await tester.startGesture(
      tester.getCenter(find.text('Apples')),
      kind: PointerDeviceKind.mouse,
    );
    await click.up();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(items.single['checked'], true);
    await tester.pumpWidget(const SizedBox());
  });

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
      matching: find.byWidgetPredicate((widget) => widget is Draggable<String>),
    );
    final mouseDraggable = draggable.first;
    final originalState = tester.state(mouseDraggable);
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
      expect(tester.state(mouseDraggable), same(originalState));
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
