import 'package:coffey_table_recipes/src/parent_categories.dart';
import 'package:coffey_table_recipes/src/administration.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('failed automatic cover keeps category and offers retry', (
    tester,
  ) async {
    var generated = false;
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ParentCategories(
          request: (path, {body}) async {
            if (path.endsWith('/category-image')) {
              expect(path, '/admin/parent-categories/7/category-image');
              expect(body, isEmpty);
              generated = true;
              return {'image_url': 'https://example.test/category-7.jpg'};
            }
            reads++;
            return {
              'categories': [
                {
                  'id': '7',
                  'label': 'Pantry',
                  'can_delete': true,
                  'needs_ai_image': !generated,
                },
              ],
              'cover_warning': generated
                  ? null
                  : 'Category added, but its AI cover could not be generated.',
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pantry'), findsOneWidget);
    expect(find.textContaining('could not be generated'), findsOneWidget);
    await tester.tap(find.byTooltip('Generate cover for Pantry'));
    await tester.pumpAndSettle();
    expect(generated, isTrue);
    expect(reads, 2);
    expect(find.byTooltip('Generate cover for Pantry'), findsNothing);
    expect(find.textContaining('could not be generated'), findsNothing);
  });
  testWidgets('administrator panel opens parent category management', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdministrationPage(
          request: (path, {body}) async {
            if (path == '/me') {
              return {
                'user': {'id': '1', 'account_role': 'administrator'},
              };
            }
            if (path == '/admin/users') {
              return {'users': [], 'people': [], 'households': []};
            }
            expect(path, '/admin/parent-categories');
            return {'categories': []};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage parent categories'));
    await tester.pumpAndSettle();
    expect(find.byType(ParentCategories), findsOneWidget);
    expect(find.text('Add parent category'), findsOneWidget);
  });
  testWidgets(
    'add, rename and delete empty parents; nonempty delete disabled',
    (tester) async {
      final rows = <Map<String, dynamic>>[
        {
          'id': '1',
          'label': 'Meals',
          'child_count': 1,
          'assignment_count': 0,
          'can_delete': false,
        },
        {
          'id': '2',
          'label': 'Snacks',
          'child_count': 0,
          'assignment_count': 0,
          'can_delete': true,
        },
      ];
      final writes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ParentCategories(
            request: (path, {body}) async {
              expect(path, '/admin/parent-categories');
              if (body != null) {
                writes.add(body['action'] as String);
                if (body['action'] == 'add') {
                  rows.add({
                    'id': '3',
                    'label': body['label'],
                    'can_delete': true,
                  });
                }
                if (body['action'] == 'rename') {
                  rows.firstWhere((r) => r['id'] == body['id'])['label'] =
                      body['label'];
                }
                if (body['action'] == 'delete') {
                  rows.removeWhere((r) => r['id'] == body['id']);
                }
              }
              return {'categories': rows};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip ==
                        'Only empty parent categories can be deleted',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Add parent category'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Baking');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Baking'), findsOneWidget);
      await tester.tap(find.byTooltip('Rename Snacks'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Quick bites');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Quick bites'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete Quick bites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, ['add', 'rename']);
      await tester.tap(find.byTooltip('Delete Quick bites'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Quick bites'), findsNothing);
      expect(writes, ['add', 'rename', 'delete']);
    },
  );

  testWidgets('server rejection is shown and categories remain', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ParentCategories(
          request: (path, {body}) async {
            if (body != null) {
              throw ApiException(
                409,
                'Only empty parent categories can be deleted.',
              );
            }
            return {
              'categories': [
                {'id': '1', 'label': 'Snacks', 'can_delete': true},
              ],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Snacks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text('Only empty parent categories can be deleted.'),
      findsOneWidget,
    );
    expect(find.text('Snacks'), findsOneWidget);
  });
}
