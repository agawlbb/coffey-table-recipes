import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/account_panel.dart';

import 'home_design_test.dart' show TestUser;

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/child_mode.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_chat.dart';
import 'package:coffey_table_recipes/src/recipe_editor.dart';
import 'package:coffey_table_recipes/src/recipe_import.dart';
import 'package:coffey_table_recipes/src/shopping_socket.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> chatReply(
  int revision, {
  bool ready = true,
  Map<String, dynamic>? recipe,
  String recipeText = 'Egg soup\n\nIngredients\n2 eggs\n2 cups water\n\nMethod\n1. Simmer for 2 minutes.',
}) => {
  'message': revision == 1
      ? 'We can make a savory egg soup.'
      : 'Removing eggs makes a thinner soup. I updated the working recipe.',
  'ready': ready,
  'recipe_text': recipeText,
  'working_recipe': chatRecipe(),
  'revision': revision,
  if (recipe != null) 'draft': {'recipe': recipe, 'questions': []},
};

Map<String, dynamic> chatRecipe({String? id, bool variation = false}) => {
  'id': ?id,
  if (id != null) 'revision': 3,
  'title': 'Egg soup',
  'original_language': 'en',
  'measurement_system': 'us',
  'import_key': 'stable-chat-key',
  'source_type': variation ? 'ai_variation' : 'ai_created',
  if (variation) 'parent_recipe_id': '10',
  'ingredients': [
    {'id': 'new-i', 'original_text': '2 eggs', 'ingredient_name': 'eggs'},
  ],
  'steps': [
    {'id': 'new-s', 'instruction': 'Simmer for 2 minutes.'},
  ],
};

Future<void> openChat(
  WidgetTester tester,
  RecipeSave request, {
  bool existing = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecipeChat(
                  householdId: '2',
                  request: request,
                  recipeId: existing ? '10' : null,
                  recipeTitle: existing ? 'Original soup' : null,
                ),
              ),
            ),
            child: const Text('Open chat'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open chat'));
  await tester.pumpAndSettle();
}

Future<void> send(WidgetTester tester, String message) async {
  await tester.enterText(find.widgetWithText(TextField, 'Message AI'), message);
  await tester.pump();
  await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    offlineStatus.value = false;
    childMode.value = false;
  });
  tearDown(() {
    offlineStatus.value = false;
    childMode.value = false;
  });

  testWidgets(
    'direct save failure retains draft and reuses the same receipt without preparing again',
    (tester) async {
      var chats = 0;
      final saves = <Map<String, dynamic>>[];
      await openChat(tester, (path, body) async {
        if (path.endsWith('/recipe-chat')) {
          chats++;
          return chatReply(
            chats,
            recipe: body['action'] == 'prepare' ? chatRecipe() : null,
          );
        }
        saves.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
        if (saves.length == 1) throw TimeoutException('Response lost');
        return {
          'recipe': {...body, 'id': '11'},
        };
      });
      await send(tester, 'Make soup');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.textContaining('Could not confirm the save'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(chats, 2);
      expect(saves, hasLength(2));
      expect(saves[0], saves[1]);
      expect(saves[0]['client_save_id'], matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(find.text('Open chat'), findsOneWidget);
    },
  );

  testWidgets(
    'lost responses recover the same turn before accepting a different message',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      await openChat(tester, (_, body) async {
        bodies.add(Map.from(body));
        if (bodies.length == 1) throw TimeoutException('Response lost');
        return chatReply(1);
      });
      await send(tester, 'Make soup');
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
      await tester.pumpAndSettle();
      expect(bodies[0], bodies[1]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      expect(find.text('You'), findsOneWidget);
    },
  );

  testWidgets(
    'preparation failure retries the same request without another chat turn',
    (tester) async {
      final attempts = <Map<String, dynamic>>[];
      await openChat(tester, (path, body) async {
        if (!path.endsWith('/recipe-chat')) {
          return {
            'recipe': {...body, 'id': '11'},
          };
        }
        if (body['action'] == 'message') return chatReply(1);
        attempts.add(Map.from(body));
        if (attempts.length == 1) throw TimeoutException('Response lost');
        return chatReply(2, recipe: chatRecipe());
      });
      await send(tester, 'Make soup');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditor), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(attempts[0], attempts[1]);
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.text('Open chat'), findsOneWidget);
    },
  );

  testWidgets(
    'direct variation save retains the copied cover and attribution',
    (tester) async {
      Map<String, dynamic>? saved;
      await openChat(tester, (path, body) async {
        if (!path.endsWith('/recipe-chat')) {
          saved = body;
          return {
            'recipe': {...body, 'id': '11'},
          };
        }
        return chatReply(
          (body['revision'] as int) + 1,
          recipe: body['action'] == 'prepare'
              ? {
                  ...chatRecipe(variation: true),
                  'photos': [
                    {
                      'id': 'new-cover',
                      'image_base64': 'fixture-bytes',
                      'is_cover': 1,
                      'attribution': 'Original photographer',
                    },
                  ],
                }
              : null,
        );
      }, existing: true);
      await send(tester, 'Improve soup');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as a new variation'));
      await tester.pumpAndSettle();
      expect(
        (saved!['photos'] as List).single['image_base64'],
        'fixture-bytes',
      );
      expect(
        (saved!['photos'] as List).single['attribution'],
        'Original photographer',
      );
      expect(find.byType(RecipeEditor), findsNothing);
    },
  );

  testWidgets('shared edits retain confirmation without opening an editor', (
    tester,
  ) async {
    var saves = 0;
    await openChat(tester, (path, body) async {
      if (path.endsWith('/recipe-chat')) {
        return chatReply(
          (body['revision'] as int) + 1,
          recipe: body['action'] == 'prepare'
              ? {...chatRecipe(id: '10'), 'household_count': 2}
              : null,
        );
      }
      saves++;
      expect(body['confirm_shared_edit'], isTrue);
      return {
        'recipe': {...body, 'id': '10'},
      };
    }, existing: true);
    await send(tester, 'Change soup');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update the existing recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Save recipe changes?'), findsOneWidget);
    expect(saves, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeEditor), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update the existing recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save for all households'));
    await tester.pumpAndSettle();
    expect(saves, 1);
  });

  testWidgets(
    'created dish saves and opens the recipe viewer from Add recipe',
    (tester) async {
      var writes = 0;
      final recipe = {
        ...chatRecipe(),
        'id': '11',
        'revision': 1,
        'photos': [],
        'groups': [],
        'actions': [],
        'category_assignments': [],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(
            user: TestUser(),
            request: (path, {body}) async {
              if (path == '/me') {
                return {
                  'user': {
                    'id': '42',
                    'account_role': 'member',
                    'child_mode': false,
                  },
                  'households': [
                    {'id': '2', 'name': 'Family', 'role': 'owner'},
                  ],
                };
              }
              if (path.endsWith('/recipe-chat')) {
                return chatReply(
                  (body!['revision'] as int) + 1,
                  recipe: body['action'] == 'prepare' ? chatRecipe() : null,
                );
              }
              if (path == '/households/2/recipes' && body != null) {
                writes++;
                return {'recipe': recipe};
              }
              if (path == '/households/2/recipes/11') return {'recipe': recipe};
              if (path.endsWith('/people') || path.endsWith('/favorites')) {
                return {'people': []};
              }
              return {'recipes': [], 'next_offset': null};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add recipe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create with AI'));
      await tester.pumpAndSettle();
      await send(tester, 'Make soup');
      expect(find.text('View changes'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.byType(RecipeDetail), findsOneWidget);
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.text('Egg soup').first, findsOneWidget);
    },
  );

  test('chat routes exclusively through the VPS AI scope', () {
    expect(isAiPath('/households/2/recipe-chat'), isTrue);
    expect(isVpsDataPath('/households/2/recipe-chat'), isFalse);
    expect(isAiPath('/households/2/recipe-chat/extra'), isFalse);
  });

  testWidgets('Add recipe opens conversational creation for any household', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeImport(
          householdId: '2',
          request: (_, _) async {
            calls++;
            return {};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create with AI'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeChat), findsOneWidget);
    expect(find.text('AI'), findsNothing);
    expect(calls, 0);
  });

  testWidgets(
    'back-and-forth stays open when ready and Save bypasses the editor',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await openChat(tester, (path, body) async {
        calls.add({'path': path, 'body': jsonDecode(jsonEncode(body))});
        if (path.endsWith('/recipe-chat')) {
          final revision = (body['revision'] as int) + 1;
          return chatReply(
            revision,
            recipe: body['action'] == 'prepare' ? chatRecipe() : null,
          );
        }
        return {
          'recipe': {...body, 'id': '11'},
        };
      });
      await send(tester, 'Create a savory egg soup');
      expect(find.text('You'), findsOneWidget);
      expect(find.text('We can make a savory egg soup.'), findsOneWidget);
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      await send(tester, 'What if I remove the eggs?');
      expect(find.text('Create a savory egg soup'), findsOneWidget);
      expect(find.text('What if I remove the eggs?'), findsOneWidget);
      expect(find.textContaining('updated the working recipe'), findsOneWidget);
      expect(find.byType(RecipeEditor), findsNothing);
      expect(
        (calls.first['body'] as Map)['request_id'],
        (calls.last['body'] as Map)['request_id'],
      );
      expect((calls.last['body'] as Map)['revision'], 1);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.text('Open chat'), findsOneWidget);
      expect(calls.length, 4);
      expect(
        calls
            .take(3)
            .every((c) => (c['path'] as String).endsWith('/recipe-chat')),
        isTrue,
      );
      expect(calls.last['path'], '/households/2/recipes');
      expect((calls.last['body'] as Map)['import_key'], 'stable-chat-key');
      expect((calls.last['body'] as Map)['source_type'], 'ai_created');
      expect(find.text('Open chat'), findsOneWidget);
    },
  );

  for (final edit in [false, true]) {
    testWidgets(
      '${edit ? 'edit' : 'variation'} outcome uses the intended save route',
      (tester) async {
        final calls = <Map<String, dynamic>>[];
        await openChat(tester, (path, body) async {
          calls.add({'path': path, 'body': jsonDecode(jsonEncode(body))});
          if (path.endsWith('/recipe-chat')) {
            return chatReply(
              (body['revision'] as int) + 1,
              recipe: body['action'] == 'prepare'
                  ? chatRecipe(id: edit ? '10' : '999', variation: !edit)
                  : null,
            );
          }
          return {
            'recipe': {...body, 'id': edit ? '10' : '11'},
          };
        }, existing: true);
        expect(
          find.byType(DropdownButtonFormField<RecipeChatOutcome>),
          findsNothing,
        );
        await send(tester, 'Make it richer');
        expect((calls.first['body'] as Map)['mode'], 'existing');
        expect((calls.first['body'] as Map)['recipe_id'], '10');
        expect(
          find.byType(DropdownButtonFormField<RecipeChatOutcome>),
          findsNothing,
        );
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('How should this recipe be saved?'), findsOneWidget);
        await tester.tap(
          find.text(
            edit ? 'Update the existing recipe' : 'Save as a new variation',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          (calls[calls.length - 2]['body'] as Map)['save_as'],
          edit ? 'edit' : 'variation',
        );
        expect(
          calls.last['path'],
          edit ? '/households/2/recipes/10' : '/households/2/recipes',
        );
        if (!edit) {
          expect((calls.last['body'] as Map)['parent_recipe_id'], '10');
        }
      },
    );
  }

  testWidgets(
    'unchanged retries reuse turn identity and retain input without duplicate bubbles',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      await openChat(tester, (_, body) async {
        bodies.add(Map.from(body));
        if (bodies.length == 1) {
          throw ApiException(503, 'Temporary outage', code: 'ai_unavailable');
        }
        return chatReply(1);
      });
      await send(tester, 'Make soup');
      expect(find.text('Temporary outage'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Make soup',
      );
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
      await tester.pumpAndSettle();
      expect(bodies[0], bodies[1]);
      expect(find.text('Make soup'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
    },
  );

  testWidgets(
    'editing a failed message creates a fresh turn without losing conversation',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      await openChat(tester, (_, body) async {
        bodies.add(Map.from(body));
        if (bodies.length == 1) {
          throw ApiException(503, 'Temporary outage', code: 'ai_unavailable');
        }
        return chatReply(1);
      });
      await send(tester, 'Make soup');
      await send(tester, 'Make stew');
      expect(bodies[0]['request_id'], bodies[1]['request_id']);
      expect(bodies[0]['turn_id'], isNot(bodies[1]['turn_id']));
      expect(find.text('Make stew'), findsOneWidget);
    },
  );

  testWidgets(
    'readiness can return to discussion and importer clarifications stay in chat',
    (tester) async {
      await openChat(
        tester,
        (_, body) async => chatReply(
          (body['revision'] as int) + 1,
          ready: body['action'] != 'prepare',
        ),
      );
      await send(tester, 'Make soup');
      await tester.enterText(find.byType(TextField), 'Wait, what about cream?');
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Make soup'), findsOneWidget);
    },
  );

  testWidgets(
    'busy sends are single-flight and cancellation ignores late replies',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await openChat(tester, (_, _) {
        calls++;
        return pending.future;
      });
      await tester.enterText(find.byType(TextField), 'Make soup');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
      await tester.pump();
      expect(find.text('AI is thinking…'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull,
      );
      expect(calls, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      pending.complete(chatReply(1));
      await tester.pumpAndSettle();
      expect(find.text('Open chat'), findsOneWidget);
      expect(find.byType(RecipeEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'generation finishing behind discard dialog leaves review available',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      await openChat(
        tester,
        (path, body) => !path.endsWith('/recipe-chat')
            ? Future.value({
                'recipe': {...body, 'id': '11'},
              })
            : body['action'] == 'prepare'
            ? pending.future
            : Future.value(chatReply(1)),
      );
      await send(tester, 'Make soup');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 300));
      pending.complete(chatReply(2, recipe: chatRecipe()));
      await tester.pumpAndSettle();
      expect(find.text('Discard recipe chat?'), findsOneWidget);
      expect(find.byType(RecipeEditor), findsNothing);
      await tester.tap(find.text('Keep chatting'));
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.text('Open chat'), findsOneWidget);
    },
  );

  testWidgets(
    'malformed response preserves retry identity and offline blocks requests',
    (tester) async {
      var calls = 0;
      await openChat(tester, (_, _) async {
        calls++;
        return {'message': 'Incomplete'};
      });
      await send(tester, 'Make soup');
      expect(find.textContaining('incomplete reply'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Make soup',
      );
      offlineStatus.value = true;
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull,
      );
      expect(calls, 1);
    },
  );

  testWidgets(
    'Request variation saves directly and opens the new variation viewer',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            householdId: '2',
            recipeId: '10',
            title: 'Original soup',
            request: (path) async => {
              'recipe': {
                ...chatRecipe(id: path.endsWith('/11') ? '11' : '10'),
                'title': path.endsWith('/11') ? 'Turkey soup' : 'Original soup',
                'in_household': true,
              },
            },
            save: (path, body) async => path.endsWith('/recipe-chat')
                ? chatReply(
                    (body['revision'] as int) + 1,
                    recipe: body['action'] == 'prepare'
                        ? chatRecipe(variation: true)
                        : null,
                  )
                : {
                    'recipe': {...body, 'id': '11', 'title': 'Turkey soup'},
                  },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request variation'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeChat), findsOneWidget);
      expect(tester.widget<RecipeChat>(find.byType(RecipeChat)).recipeId, '10');
      await send(tester, 'Improve soup');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as a new variation'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditor), findsNothing);
      expect(
        tester.widget<RecipeDetail>(find.byType(RecipeDetail)).recipeId,
        '11',
      );
    },
  );

  testWidgets(
    'compact chat supports enlarged text and keyboard without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: RecipeChat(
            householdId: '2',
            recipeId: '10',
            recipeTitle: 'Original soup',
            request: (_, _) async => chatReply(1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.widgetWithIcon(IconButton, Icons.send), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'recipe tab updates separately, highlights revisions and retains input',
    (tester) async {
      var calls = 0;
      const revised =
          'Ginger soup\n\nIngredients\n2 eggs\n1 tsp ginger\n\nMethod\n1. Simmer with ginger.';
      await openChat(tester, (_, body) async {
        expect(body['draft_view'], isTrue);
        calls++;
        return calls == 1 ? chatReply(1) : chatReply(2, recipeText: revised);
      });
      await send(tester, 'Make soup');
      expect(find.textContaining('2 cups water'), findsNothing);
      await tester.enterText(find.byType(TextField), 'What if I add ginger?');
      await tester.pump();
      await tester.tap(find.text('Draft recipe'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2 cups water', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Chat').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'What if I add ginger?',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('View changes'), findsNothing);
      await tester.tap(find.text('Draft recipe'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 tsp ginger', findRichText: true),
        findsOneWidget,
      );
      final text = tester.widget<SelectableText>(
        find.byType(SelectableText).last,
      );
      final spans = text.textSpan!.children!.cast<TextSpan>();
      expect(
        spans
            .firstWhere((s) => s.text == '1 tsp ginger\n')
            .style!
            .backgroundColor,
        isNotNull,
      );
      expect(find.byType(RecipeEditor), findsNothing);
      expect(calls, 2);
    },
  );

  testWidgets('keyboard Send submits once and preserves failed input', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    await openChat(tester, (_, _) {
      calls++;
      return pending.future;
    });
    await tester.enterText(find.byType(TextField), 'Make soup');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(calls, 1);
    pending.completeError(
      ApiException(503, 'Try again', code: 'ai_unavailable'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Make soup',
    );
  });

  testWidgets(
    'hardware Enter sends, Shift Enter inserts newline, composing Enter does not send',
    (tester) async {
      var calls = 0;
      await openChat(tester, (_, _) async {
        calls++;
        return chatReply(calls);
      });
      await tester.enterText(find.byType(TextField), 'Make');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      expect(controller.text, 'Make\n');
      expect(calls, 0);
      controller.value = const TextEditingValue(
        text: 'Soup',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, 0);
      controller.value = const TextEditingValue(
        text: 'Soup',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  for (final scenario in [
    (name: 'iPhone keyboard', size: Size(390, 844), inset: 320.0),
    (name: 'compact enlarged chat', size: Size(360, 800), inset: 300.0),
    (name: 'iPad landscape keyboard', size: Size(1024, 768), inset: 350.0),
    (name: 'iPad Bluetooth suggestion bar', size: Size(1024, 768), inset: 0.0),
    (name: 'iPad reported accessory inset', size: Size(768, 1024), inset: 44.0),
  ]) {
    testWidgets(
      '${scenario.name} keeps composer and Send clear of obstruction',
      (tester) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  scenario.name == 'compact enlarged chat' ? 1.8 : 1,
                ),
              ),
              child: child!,
            ),
            home: RecipeChat(
              householdId: '2',
              request: (_, _) async => chatReply(1),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Make soup');
        tester.view.viewInsets = FakeViewPadding(bottom: scenario.inset);
        await tester.pumpAndSettle();
        final bottom =
            scenario.size.height - (scenario.inset < 64 ? 64 : scenario.inset);
        expect(
          tester.getBottomRight(find.byType(TextField)).dy,
          lessThanOrEqualTo(bottom),
        );
        expect(
          tester.getBottomRight(find.byTooltip('Send')).dy,
          lessThanOrEqualTo(bottom),
        );
        if (scenario.inset > 0) {
          expect(
            tester.getBottomRight(find.byTooltip('Send')).dx,
            lessThanOrEqualTo(scenario.size.width - 64),
          );
        }
        await tester.tap(find.byTooltip('Send'));
        await tester.pumpAndSettle();
        expect(find.text('We can make a savory egg soup.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'a working draft can be reviewed while AI readiness is false, with progress on either tab',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await openChat(tester, (path, body) async {
        if (!path.endsWith('/recipe-chat')) {
          return {
            'recipe': {...body, 'id': '11'},
          };
        }
        calls++;
        return body['action'] == 'prepare'
            ? pending.future
            : chatReply(1, ready: false);
      });
      await send(tester, 'Make soup');
      expect(find.text('Save'), findsOneWidget);
      await tester.tap(find.text('Draft recipe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Preparing recipe…'), findsOneWidget);
      expect(calls, 2);
      await tester.tap(find.text('Chat').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(chatReply(2, recipe: chatRecipe()));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.text('Open chat'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'cancel save destination keeps chat and draft without preparing',
    (tester) async {
      var calls = 0;
      await openChat(tester, (_, body) async {
        calls++;
        return chatReply(1);
      }, existing: true);
      await send(tester, 'Improve soup');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Improve soup'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(calls, 1);
    },
  );

  testWidgets(
    'preparation failure on recipe tab keeps draft and destination for retry',
    (tester) async {
      final attempts = <Map<String, dynamic>>[];
      await openChat(tester, (path, body) async {
        if (!path.endsWith('/recipe-chat')) {
          return {
            'recipe': {...body, 'id': '10'},
          };
        }
        if (body['action'] == 'message') return chatReply(1, ready: false);
        attempts.add(Map.from(body));
        if (attempts.length == 1) {
          throw ApiException(
            502,
            'Could not prepare your working recipe for review. Your chat and draft are still here.',
            code: 'invalid_ai_reply',
          );
        }
        return chatReply(2, recipe: chatRecipe(id: '10'));
      }, existing: true);
      await send(tester, 'Improve soup');
      await tester.tap(find.text('Draft recipe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update the existing recipe'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('chat and draft are still here'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 cups water', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(attempts[0], attempts[1]);
      expect(attempts.last['save_as'], 'edit');
      expect(find.byType(RecipeEditor), findsNothing);
      expect(find.text('Open chat'), findsOneWidget);
    },
  );
  testWidgets(
    'a missing structured draft is rejected without losing the request',
    (tester) async {
      await openChat(
        tester,
        (_, _) async => chatReply(1)..remove('working_recipe'),
      );
      await send(tester, 'Make soup');
      expect(find.textContaining('incomplete reply'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Make soup',
      );
      expect(find.byType(RecipeEditor), findsNothing);
    },
  );
  testWidgets('local missing-field guidance returns from recipe view to chat', (
    tester,
  ) async {
    await openChat(tester, (_, body) async {
      if (body['action'] == 'prepare') {
        return chatReply(2, ready: false)
          ..['message'] = 'Please add cooking steps.';
      }
      return chatReply(1, ready: false);
    });
    await send(tester, 'Start soup');
    await tester.tap(find.text('Draft recipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Please add cooking steps.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    expect(find.byType(RecipeEditor), findsNothing);
  });
}
