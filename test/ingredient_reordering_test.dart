import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'holding and dragging reorders saved ingredients while preserving groups',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeEditor(
            householdId: '2',
            recipe: {
              'title': 'Soup',
              'original_language': 'en',
              'measurement_system': 'us',
              'groups': [
                {'id': 'g', 'title': 'Soup ingredients'},
              ],
              'ingredients': [
                for (final name in ['Carrot', 'Onion', 'Potato'])
                  {
                    'id': name,
                    'group_id': 'g',
                    'original_text': name,
                    'ingredient_name': name,
                  },
                {
                  'id': 'Water',
                  'original_text': 'Water',
                  'ingredient_name': 'Water',
                },
              ],
              'steps': <Map<String, dynamic>>[],
            },
            save: (_, body) async {
              saved = body;
              throw ApiException(500, 'Captured');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Go to ingredients'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Soup ingredients · 3')),
        alignment: .2,
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Carrot')),
      );
      await tester.pump(const Duration(milliseconds: 650));
      await gesture.moveTo(
        tester.getBottomLeft(find.text('Potato')) + const Offset(30, 35),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Onion')).dy,
        lessThan(tester.getTopLeft(find.text('Carrot')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Potato')).dy,
        lessThan(tester.getTopLeft(find.text('Carrot')).dy),
      );
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      final rows = saved!['ingredients'] as List;
      expect(rows.map((row) => row['id']).toList(), [
        'Onion',
        'Potato',
        'Carrot',
        'Water',
      ]);
      expect(rows.take(3).every((row) => row['group_id'] == 'g'), isTrue);
      expect(rows.last['group_id'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
