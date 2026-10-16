import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

Map<String, dynamic> draft(List<String> questions) => {
  'questions': questions,
  'recipe': {
    'title': 'Soup',
    'original_language': 'en',
    'measurement_system': 'unspecified',
    'ingredients': [
      {'id': 'new-i', 'original_text': 'Water', 'ingredient_name': 'water'},
    ],
    'steps': [
      {'id': 'new-s', 'instruction': 'Boil'},
    ],
    'source_text': 'I make soup',
    'import_key': 'abc',
  },
};

void main() {
  for (final failure in <Object>[
    TimeoutException('test timeout'),
    http.ClientException('test DNS failure'),
    <String, dynamic>{'questions': null, 'recipe': {}},
  ]) {
    testWidgets(
      'import distinguishes ${failure.runtimeType} and retains input',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: RecipeImport(
              householdId: '2',
              request: (_, _) async {
                if (failure is Map<String, dynamic>) return failure;
                throw failure;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'I mix a dough, then make a separate sauce.',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Prepare recipe'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Prepare recipe'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            failure is TimeoutException
                ? 'timed out'
                : failure is http.ClientException
                ? 'Could not connect to the recipe service'
                : 'incomplete draft',
          ),
          findsOneWidget,
        );
        expect(
          find.text('I mix a dough, then make a separate sauce.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Could not prepare your recipe.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'edit source retains input and can return to review without another AI call',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeImport(
            householdId: '2',
            request: (_, body) async {
              calls++;
              return draft([]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Original soup recipe',
      );
      await tester.ensureVisible(find.text('Prepare recipe'));
      await tester.tap(find.text('Prepare recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Draft—not saved yet'), findsOneWidget);
      await tester.ensureVisible(find.text('Edit source'));
      await tester.tap(find.text('Edit source'));
      await tester.pumpAndSettle();
      expect(find.text('Original soup recipe'), findsOneWidget);
      expect(calls, 1);
      await tester.ensureVisible(find.text('Return to review without changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return to review without changes'));
      await tester.pumpAndSettle();
      expect(find.text('Review recipe'), findsOneWidget);
      expect(calls, 1);
    },
  );

  testWidgets(
    'website cover survives clarification without resending picture bytes',
    (tester) async {
      const encoded =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT1sAAAAASUVORK5CYII=';
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeImport(
            householdId: '2',
            request: (path, body) async {
              if (path.endsWith('/recipes')) {
                saved = body;
                return {
                  'recipe': {...body, 'id': '30'},
                };
              }
              if (body['kind'] == 'answers') {
                expect((body['recipe'] as Map).containsKey('photos'), isFalse);
                return draft([]);
              }
              final data = draft(['How much water?']);
              (data['recipe'] as Map)['photos'] = [
                {
                  'id': 'new-website-photo',
                  'image_base64': encoded,
                  'is_cover': 1,
                  'attribution': 'Photo from https://example.com/soup',
                },
              ];
              return data;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Recipe source text',
      );
      await tester.ensureVisible(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.tap(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '2 cups');
      await tester.ensureVisible(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.tap(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save recipe').first);
      await tester.pumpAndSettle();
      final photo = (saved!['photos'] as List).single as Map;
      expect(photo['image_base64'], encoded);
      expect(photo['is_cover'], 1);
      expect(photo['attribution'], 'Photo from https://example.com/soup');
    },
  );
  for (final scheme in ['http', 'https']) {
    testWidgets('$scheme recipe website links reach the import backend', (
      tester,
    ) async {
      Map<String, dynamic>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeImport(
            householdId: '2',
            request: (_, body) async {
              submitted = body;
              return draft(['How much water?']);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Website').last);
      await tester.pumpAndSettle();
      final url =
          '$scheme://www.foodnetwork.com/recipes/tyler-florence/caramelized-onion-and-cornbread-stuffing-recipe3.html';
      await tester.enterText(find.byType(TextField).first, url);
      await tester.ensureVisible(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.tap(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.pumpAndSettle();
      expect(submitted?['kind'], 'website');
      expect(submitted?['url'], url);
    });
  }
  testWidgets('written description sends a distinct source label', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeImport(
          householdId: '2',
          request: (_, body) async {
            called = true;
            expect(body['kind'], 'text');
            expect(body['input_source'], 'written_description');
            return draft(['How much water?']);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Describe how I make a dish').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'I make soup');
    await tester.ensureVisible(
      find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
    );
    await tester.tap(find.textContaining(RegExp(r'^(Prepare|Update) recipe$')));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(find.text('How much water?'), findsOneWidget);
  });

  for (final edited in [false, true]) {
    testWidgets('cancel import review returns to origin (edited: $edited)', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecipeImport(
                      householdId: '2',
                      request: (_, body) async {
                        calls++;
                        return draft([]);
                      },
                    ),
                  ),
                ),
                child: const Text('Start import'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start import'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Paste your recipe'),
        'Soup with water',
      );
      await tester.ensureVisible(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.tap(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review recipe'), findsOneWidget);
      if (edited) {
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Recipe name'),
          'Changed soup',
        );
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      if (edited) {
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Start import'), findsOneWidget);
      expect(find.text('Add recipe'), findsNothing);
      expect(find.text('Discard recipe import?'), findsNothing);
      expect(calls, 1);
    });
  }
  for (final camera in [false, true]) {
    testWidgets(
      camera
          ? 'camera sends captured image for extraction'
          : 'PDF sends original file for extraction',
      (tester) async {
        Map<String, dynamic>? sent;
        final bytes = utf8.encode(
          camera ? 'image fixture' : '%PDF-1.7 fixture',
        );
        Future<XFile?> pick() async =>
            XFile.fromData(bytes, path: camera ? 'photo.jpg' : 'recipe.pdf');
        await tester.pumpWidget(
          MaterialApp(
            home: RecipeImport(
              householdId: '2',
              pickFile: pick,
              takePhoto: pick,
              request: (_, body) async {
                sent = body;
                return draft(['How much water?']);
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text(camera ? 'Camera' : 'File').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            camera ? 'Take a picture' : 'Choose PDF, image, or text file',
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
        );
        await tester.tap(
          find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
        );
        await tester.pumpAndSettle();
        expect(sent?['kind'], camera ? 'camera' : 'file');
        expect(base64Decode(sent!['file_base64'] as String), bytes);
        expect(find.text('How much water?'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'description asks questions before review and saves only on Save',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeImport(
            householdId: '2',
            request: (path, body) async {
              calls.add(path);
              if (path.endsWith('/recipes')) {
                return {
                  'recipe': {...body, 'id': '30'},
                };
              }
              if (body['kind'] == 'answers') {
                expect((body['answers'] as List).first['answer'], '2 cups');
                return draft([]);
              }
              expect(body['text'], 'I make soup');
              return draft(['How much water?']);
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'I make soup');
      await tester.ensureVisible(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.tap(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.pumpAndSettle();
      expect(find.text('How much water?'), findsOneWidget);
      expect(calls.length, 1);
      await tester.enterText(find.byType(TextField).first, '2 cups');
      await tester.ensureVisible(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.tap(
        find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review recipe'), findsOneWidget);
      expect(calls.length, 2);
      await tester.tap(find.text('Save recipe').first);
      await tester.pumpAndSettle();
      expect(calls.last, '/households/2/recipes');
    },
  );
  testWidgets('failed AI call retains original text for retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeImport(
          householdId: '2',
          request: (_, _) async => throw ApiException(503, 'AI unavailable'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'My recipe');
    await tester.ensureVisible(
      find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
    );
    await tester.tap(find.textContaining(RegExp(r'^(Prepare|Update) recipe$')));
    await tester.pumpAndSettle();
    expect(find.text('AI unavailable'), findsOneWidget);
    expect(find.text('My recipe'), findsOneWidget);
  });
  testWidgets('upload reads text locally without sending binary attachment', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeImport(
          householdId: '2',
          pickFile: () async => XFile.fromData(
            utf8.encode('Recipe text'),
            name: 'recipe.txt',
            path: 'recipe.txt',
          ),
          request: (_, body) async {
            sent = body;
            return draft(['How much water?']);
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('File').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose PDF, image, or text file'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.textContaining(RegExp(r'^(Prepare|Update) recipe$')),
    );
    await tester.tap(find.textContaining(RegExp(r'^(Prepare|Update) recipe$')));
    await tester.pumpAndSettle();
    expect(sent?['kind'], 'text');
    expect(sent?['text'], 'Recipe text');
    expect(sent?.containsKey('file_base64'), false);
  });
}
