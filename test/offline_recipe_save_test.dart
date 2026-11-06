import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_chat_test.dart' show openChat, send, chatReply, chatRecipe;

void main() {
  for (final existing in [false, true]) {
    testWidgets(
      'AI recipe save explains local retention (existing=$existing)',
      (tester) async {
        final disk = <String, String>{};
        final pending = LocalData(
          key: 'fixture',
          fetch: (_) async => {},
          send: (_, _) async => {},
          readStore: (key) async => disk[key],
          writeStore: (key, value) async {
            disk[key] = value;
          },
        );
        await openChat(tester, (path, body) async {
          if (path.endsWith('/recipe-chat')) {
            return chatReply(
              (body['revision'] as int) + 1,
              recipe: body['action'] == 'prepare'
                  ? chatRecipe(id: existing ? '10' : null)
                  : null,
            );
          }
          return pending.save(path, body);
        }, existing: existing);
        await send(tester, 'Make soup');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        if (existing) {
          await tester.tap(find.text('Update the existing recipe'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Open chat'), findsOneWidget);
        expect(
          find.textContaining(
            existing
                ? 'We’ll ask before sending'
                : 'will upload when you reconnect',
          ),
          findsOneWidget,
        );
        expect(pending.pendingChanges, hasLength(1));
        expect(pending.pendingChanges.single['review'], existing);
        await tester.pumpWidget(const SizedBox());
        pending.dispose();
      },
    );
  }
}
