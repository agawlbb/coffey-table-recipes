import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:better_share_handler/better_share_handler.dart';
import 'package:coffey_table_recipes/src/shared_recipe_import.dart';
import 'package:coffey_table_recipes/src/recipe_import.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeShares extends ShareHandlerPlatform {
  final controller = StreamController<SharedMedia>.broadcast();
  var resets = 0;
  @override
  Future<SharedMedia?> getInitialSharedMedia() async =>
      SharedMedia(content: 'Cold recipe');
  @override
  Future<void> resetInitialSharedMedia() async {
    resets++;
  }

  @override
  Stream<SharedMedia> get sharedMediaStream => controller.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('iOS saved shares copy files before acknowledgement and do not duplicate on retry', () async {
    const channel = MethodChannel('coffey_table_recipes/share_inbox');
    final folder = await Directory.systemTemp.createTemp('ios-recipe-share-');
    final file = File('${folder.path}/recipe.txt');
    await file.writeAsString('Shared cookie recipe');
    final inbox = SharedRecipeInbox();
    var acknowledged = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pending') {
            return [
              {
                'id': 'fixture-share',
                'content': '',
                'attachments': [
                  {'path': file.path},
                ],
              },
            ];
          }
          expect(
            await inbox.value.first.file!.readAsString(),
            'Shared cookie recipe',
          );
          acknowledged++;
          if (acknowledged == 1) throw PlatformException(code: 'retry');
          await file.delete();
          return null;
        });
    try {
      await inbox.readSavedIOSShares();
      await inbox.readSavedIOSShares();
      expect(acknowledged, 2);
      expect(inbox.value.where((input) => input.file != null).length, 1);
      expect(
        await inbox.value.first.file!.readAsString(),
        'Shared cookie recipe',
      );
    } finally {
      inbox.dispose();
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await folder.delete(recursive: true);
    }
  });
  test(
    'cold and running shares are queued until a household consumes them',
    () async {
      final previous = ShareHandlerPlatform.instance;
      final fake = FakeShares();
      ShareHandlerPlatform.instance = fake;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final inbox = SharedRecipeInbox();
      try {
        await inbox.start();
        fake.controller.add(SharedMedia(content: 'https://example.com/recipe'));
        await Future<void>.delayed(Duration.zero);
        expect(inbox.value.length, 2);
        expect(inbox.take()!.text, 'Cold recipe');
        expect(inbox.take()!.url, 'https://example.com/recipe');
        expect(inbox.take(), isNull);
        expect(fake.resets, 1);
      } finally {
        inbox.dispose();
        await fake.controller.close();
        ShareHandlerPlatform.instance = previous;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  test('staging bytes survive removal of the original and captions are not separate recipes', () async {
    final folder = await Directory.systemTemp.createTemp('recipe-share-test-');
    final file = File('${folder.path}/recipe.txt');
    await file.writeAsString('Recipe text');
    final inbox = SharedRecipeInbox();
    try {
      await inbox.receive(
        SharedMedia(
          content: 'A caption',
          attachments: [
            SharedAttachment(path: file.path, type: SharedAttachmentType.file),
          ],
        ),
      );
      await file.delete();
      expect(inbox.value.length, 1);
      expect(await inbox.take()!.file!.readAsString(), 'Recipe text');
    } finally {
      inbox.dispose();
      await folder.delete(recursive: true);
    }
  });
  for (final file in [false, true]) {
    testWidgets(
      'shared ${file ? 'text file' : 'text'} automatically attempts import and waits for review',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: RecipeImport(
              householdId: '2',
              sharedInput: file
                  ? SharedRecipeInput(
                      file: XFile.fromData(
                        utf8.encode('Shared recipe'),
                        name: 'recipe.txt',
                        path: 'recipe.txt',
                      ),
                    )
                  : const SharedRecipeInput(text: 'Shared recipe'),
              request: (path, body) async {
                calls++;
                expect(path, endsWith('/recipe-import'));
                expect(body['text'], 'Shared recipe');
                expect(body['kind'], 'text');
                return {
                  'questions': ['How much water?'],
                  'recipe': {
                    'title': 'Soup',
                    'ingredients': [],
                    'steps': [],
                    'source_text': 'Shared recipe',
                    'import_key': 'fixture',
                  },
                };
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.text('How much water?'), findsOneWidget);
      },
    );
  }
}
