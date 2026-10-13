import 'dart:ui' as ui;
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:coffey_table_recipes/src/recipe_import.dart';
import 'package:file_selector/file_selector.dart';

import 'package:coffey_table_recipes/src/recipe_image_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> fixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 2, 3), Paint()..color = Colors.red);
  canvas.drawRect(
    const Rect.fromLTWH(1, 0, 1, 3),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(2, 3);
  } finally {
    picture.dispose();
  }
}

Future<List<int>> pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  return data!.buffer.asUint8List(data.offsetInBytes + offset, 4).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('initial image import submits the applied edited PNG', (
    tester,
  ) async {
    final bytes = await tester.runAsync(() async {
      final image = await fixture();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List();
      } finally {
        image.dispose();
      }
    });
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeImport(
          householdId: '2',
          pickFile: () async =>
              XFile.fromData(bytes!, name: 'recipe.png', path: 'recipe.png'),
          request: (_, body) async {
            submitted = body;
            return {
              'recipe': {'title': 'Cookies'},
              'questions': ['How much sugar?'],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pasted recipe text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload a file').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose PDF, image, or text file'));
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    await tester.tap(find.text('Edit picture'));
    Future<void> settleImage() async {
      await tester.pump(const Duration(milliseconds: 350));
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
    }

    await settleImage();
    await tester.tap(find.byTooltip('Rotate right'));
    await settleImage();
    await tester.tap(find.text('Apply'));
    await settleImage();
    expect(find.text('recipe-edited.png'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        base64Decode(submitted!['file_base64'] as String),
      );
      final image = (await codec.getNextFrame()).image;
      try {
        expect([image.width, image.height], [3, 2]);
      } finally {
        image.dispose();
        codec.dispose();
      }
    });
  });
  testWidgets(
    'photo edits can be cancelled or applied and preserve cover and credit',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final image = await fixture();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      });
      Map<String, dynamic>? submitted;
      final original = base64Encode(bytes!);
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeEditor(
            householdId: '2',
            recipe: {
              'id': '9',
              'revision': 1,
              'title': 'Test recipe',
              'photos': [
                {
                  'id': '1',
                  'image_base64': original,
                  'is_cover': 1,
                  'caption': 'Cookies',
                  'attribution': 'Family',
                },
              ],
            },
            save: (_, body) async {
              submitted = body;
              throw ApiException(500, 'Test save');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> expand(String label) async {
        final target = find.text(label).last;
        await tester.ensureVisible(target);
        final tile = tester.widget<ExpansionTile>(
          find.ancestor(of: target, matching: find.byType(ExpansionTile)).first,
        );
        if (!tile.controller!.isExpanded) await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await expand('Photos');
      await expand('Photo 1 · Cover');
      Future<void> settleImage() async {
        await tester.pump(const Duration(milliseconds: 350));
        for (var attempt = 0; attempt < 40; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
      }

      final edit = find.widgetWithText(OutlinedButton, 'Edit picture');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await settleImage();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((submitted!['photos'] as List).first['image_base64'], original);
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await settleImage();
      await tester.tap(find.byTooltip('Rotate right'));
      await settleImage();
      await tester.tap(find.text('Apply'));
      await settleImage();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final photo = (submitted!['photos'] as List).first as Map;
      expect(photo['id'], '1');
      expect(photo['is_cover'], 1);
      expect(photo['attribution'], 'Family');
      expect(photo['caption'], 'Cookies');
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          base64Decode(photo['image_base64'] as String),
        );
        final image = (await codec.getNextFrame()).image;
        try {
          expect([image.width, image.height], [3, 2]);
        } finally {
          image.dispose();
          codec.dispose();
        }
      });
    },
  );
  test('crop rotate and flip retain the selected image pixels', () async {
    final original = await fixture();
    final crop = await transformRecipeImage(
      original,
      crop: const Rect.fromLTRB(.5, 0, 1, 1),
    );
    final rotate = await transformRecipeImage(original, turns: 1);
    final flip = await transformRecipeImage(original, flip: true);
    final resized = await transformRecipeImage(original, longestSide: 2);
    try {
      expect([crop.width, crop.height], [1, 3]);
      expect(await pixel(crop, 0, 1), [33, 150, 243, 255]);
      expect([rotate.width, rotate.height], [3, 2]);
      expect(await pixel(rotate, 1, 0), [244, 67, 54, 255]);
      expect(await pixel(rotate, 1, 1), [33, 150, 243, 255]);
      expect(await pixel(flip, 0, 1), [33, 150, 243, 255]);
      expect([resized.width, resized.height], [1, 2]);
    } finally {
      original.dispose();
      crop.dispose();
      rotate.dispose();
      flip.dispose();
      resized.dispose();
    }
  });
}
