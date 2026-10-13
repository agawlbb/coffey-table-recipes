import 'dart:convert';
import 'dart:ui' as ui;

import 'package:coffey_table_recipes/src/source_photo_crop.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const image =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP4z8DAAMIM/4EAAB/uBfsL2WiLAAAAAElFTkSuQmCC';
Map<String, dynamic> suggestion() => {
  'image_base64': image,
  'crop': {'left': 0.5, 'top': 0, 'right': 1, 'bottom': 1},
  'caption': 'Source picture',
  'attribution': 'From imported image',
};
Map<String, dynamic> draft() => {
  'title': 'Soup',
  'original_language': 'en',
  'measurement_system': 'us',
  'ingredients': [],
  'steps': [],
  'photos': [],
  'actions': [],
  'groups': [],
  'tags': [],
  'category_assignments': [],
  'pairings': [],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('source crop reuses only the selected image area', () async {
    final result = await prepareSourcePhoto(suggestion());
    final codec = await ui.instantiateImageCodec(
      base64Decode(result['image_base64'] as String),
    );
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1);
    expect(frame.image.height, 2);
    expect(result['attribution'], 'From imported image');
    frame.image.dispose();
    codec.dispose();
  });
  testWidgets('source picture is optional and only selected photos are saved', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final recipe = draft()..['photo_suggestions'] = [suggestion()];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: recipe,
          householdId: '2',
          save: (_, body) async {
            submitted = body;
            throw ApiException(500, 'Draft retained');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Photos').last);
    await tester.pump();
    for (
      var i = 0;
      i < 50 && find.text('Use this picture').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Use this picture'), findsOneWidget);
    expect(submitted, isNull);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use this picture'));
    await tester.tap(find.text('Use this picture'));
    await tester.pumpAndSettle();
    expect(find.text('Generate an image with AI'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((submitted!['photos'] as List).length, 1);
    expect((submitted!['photos'] as List).first['is_cover'], 1);
    expect(submitted!.containsKey('photo_suggestions'), isFalse);
  });
  testWidgets('existing category can be replaced with a typed new category', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final recipe = draft()
      ..['category_assignments'] = [
        {'category_id': '2'},
      ]
      ..['edit_options'] = {
        'categories': [
          {'id': '1', 'label': 'Desserts', 'parent_label': null},
          {'id': '2', 'label': 'Cookies', 'parent_label': 'Desserts'},
        ],
      };
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: recipe,
          householdId: '2',
          save: (_, body) async {
            submitted = body;
            throw ApiException(500, 'Draft retained');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Categories & tags'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Desserts / Cookies'));
    await tester.tap(find.text('Desserts / Cookies'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search categories'),
      'Tarts',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create "Tarts"'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Category name'),
      'Tarts',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final category = (submitted!['category_assignments'] as List).single as Map;
    expect(category['label'], 'Tarts');
    expect(category['parent_label'], 'Desserts');
    expect(category['category_id'], isNull);
    await tester.ensureVisible(find.text('Desserts / Tarts'));
    await tester.tap(find.text('Desserts / Tarts'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search categories'),
      'Cookies',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desserts / Cookies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final existing = (submitted!['category_assignments'] as List).single as Map;
    expect(existing['category_id'], '2');
    expect(existing.containsKey('label'), isFalse);
    expect(existing.containsKey('_new_category'), isFalse);
  });
}
