import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';

void main() {
  testWidgets('Add item stays visible and usable with a phone keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var items = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '7',
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
    final add = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Add item',
    );
    expect(tester.widget<IconButton>(add).onPressed, isNotNull);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(items, isEmpty);
    await tester.enterText(find.byType(TextField), 'Apples');
    await tester.pump();
    expect(tester.getRect(add).bottom, lessThan(544));
    final fieldRect = tester.getRect(find.byType(TextField));
    final addRect = tester.getRect(add);
    expect(addRect.left, greaterThanOrEqualTo(fieldRect.right));
    expect((addRect.center.dy - fieldRect.center.dy).abs(), lessThan(1));
    expect(find.text('Add item'), findsNothing);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(items.single['name'], 'Apples');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'adds, checks, has no item edit screen, and removes checked items',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      expect(find.text('Our table'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Milk');
      await tester.pump();
      await tester.tap(find.byTooltip('Add item'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Milk'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Milk'), findsOneWidget);
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text('Milk'));
      expect(text.style?.decoration, TextDecoration.lineThrough);
      expect(items.single['checked'], true);
      expect(find.byType(Checkbox), findsNothing);
      expect(
        tester.getTopLeft(find.text('Milk')).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('completed-section'))).dy,
        ),
      );
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Shopping item'), findsNothing);
      expect(items.single['department'], '');
      expect(items.single['checked'], false);
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove checked off'));
      await tester.pumpAndSettle();
      expect(items, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'server remembered assignment is displayed as soon as adding finishes',
    (tester) async {
      var items = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ShoppingListScreen(
            householdId: '7',
            householdName: 'Our table',
            request: (path, {body}) async {
              if (body != null) {
                final added = Map<String, dynamic>.from(
                  (body['items'] as List).last as Map,
                );
                expect(added['department'], '');
                items = [
                  {...added, 'department': 'Farm stand'},
                ];
              }
              return {
                'revision': items.isEmpty ? 0 : 1,
                'items': items,
                'departments': ['Farm stand'],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'GreenOnions');
      await tester.tap(find.byTooltip('Add item'));
      await tester.pumpAndSettle();
      expect(find.text('GreenOnions'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('GreenOnions')).dy,
        greaterThan(tester.getTopLeft(find.text('Farm stand')).dy),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'tap groups checked items at the bottom and restores their original departments',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var items = <Map<String, dynamic>>[
        {
          'id': 'a',
          'name': 'Apples',
          'department': 'Produce',
          'checked': false,
        },
        {'id': 'b', 'name': 'Butter', 'department': 'Dairy', 'checked': false},
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
                items = (body['items'] as List).cast<Map<String, dynamic>>();
              }
              return {
                'revision': revision,
                'items': items,
                'departments': ['Produce', 'Dairy'],
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Apples')).dx,
        greaterThan(tester.getTopLeft(find.text('Produce')).dx),
      );
      final heading = tester.widget<Text>(find.text('Produce'));
      expect(heading.style!.fontSize, 22);
      expect(heading.style!.fontWeight, FontWeight.w700);
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.text('Apples'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Apples')).dy,
        greaterThan(tester.getTopLeft(find.text('Butter')).dy),
      );
      expect(items.first['department'], 'Produce');
      await tester.tap(find.text('Butter'));
      await tester.pumpAndSettle();
      for (final name in ['Apples', 'Butter']) {
        expect(
          tester.getTopLeft(find.text(name)).dy,
          greaterThan(
            tester
                .getTopLeft(find.byKey(const ValueKey('completed-section')))
                .dy,
          ),
        );
      }
      final move = await tester.startGesture(
        tester.getCenter(find.text('Apples')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await move.moveTo(tester.getBottomRight(find.text('Butter')));
      await tester.pump(const Duration(milliseconds: 100));
      await move.up();
      await tester.pumpAndSettle();
      expect(items.every((i) => i['checked'] == true), true);
      expect(items.singleWhere((i) => i['id'] == 'a')['department'], 'Produce');
      expect(items.singleWhere((i) => i['id'] == 'b')['department'], 'Dairy');
      expect(find.text('Produce'), findsNothing);
      expect(find.text('Dairy'), findsNothing);
      expect(find.text('Apples'), findsOneWidget);
      await tester.tap(find.text('Apples'));
      await tester.pumpAndSettle();
      expect(find.text('Produce'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Apples')).dy,
        lessThan(tester.getTopLeft(find.text('Butter')).dy),
      );
      expect(items.singleWhere((i) => i['id'] == 'a')['checked'], false);
      expect(items.singleWhere((i) => i['id'] == 'a')['department'], 'Produce');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
