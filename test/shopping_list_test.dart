import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';

void main() {
  testWidgets('Add item stays visible and usable with a phone keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
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
    final add = find.widgetWithText(FilledButton, 'Add item');
    expect(tester.widget<FilledButton>(add).onPressed, isNotNull);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(items, isEmpty);
    await tester.enterText(find.byType(TextField), 'Apples');
    await tester.pump();
    expect(tester.getRect(add).bottom, lessThan(544));
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(items.single['name'], 'Apples');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'adds, checks, has no item edit screen, and removes checked items',
    (tester) async {
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
      await tester.tap(find.widgetWithText(FilledButton, 'Add item'));
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
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text('Milk'));
      expect(text.style?.decoration, TextDecoration.lineThrough);
      expect(items.single['checked'], true);
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Shopping item'), findsNothing);
      expect(items.single['department'], '');
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
      await tester.tap(find.text('Add item'));
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
}
