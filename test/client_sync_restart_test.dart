import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'transient startup storage read can recover without restarting the app',
    () async {
      var reads = 0;
      final local = LocalData(
        key: 'read-recovery',
        fetch: (_) async => {},
        send: (_, _) async => {},
        readStore: (_) async {
          if (++reads == 1) throw StateError('temporary protected storage');
          return jsonEncode({
            'data': {
              '/me': {'households': []},
            },
            'queue': [],
          });
        },
        writeStore: (_, _) async {},
      );
      addTearDown(local.dispose);
      await expectLater(local.cached('/me'), throwsStateError);
      expect(await local.cached('/me'), {'households': []});
      expect(reads, 2);
    },
  );
  for (final oldProblem in [
    null,
    'The app closed during synchronization. Review the server copy before retrying.',
    'The server accepted this change, but this device could not record the confirmation. Compare with the server before continuing.',
  ]) {
    test(
      'restart safely reconciles interrupted meal-plan save: $oldProblem',
      () async {
        var writes = 0;
        final queued = {
          'id': 'queue-id',
          'path': '/households/1/meal-plan',
          'body': {
            'operation': 'add',
            'id': 'meal-id',
            'revision': 1,
            'kind': 'leftovers',
            'date': '2099-11-05',
          },
          'sending': true,
          'saved_at': 1,
          'problem': ?oldProblem,
        };
        final canonical = {
          'revision': 2,
          'entries': [
            {'id': 'meal-id', 'kind': 'leftovers', 'plan_date': '2099-11-05'},
          ],
        };
        final local = LocalData(
          key: 'interrupted-meal',
          fetch: (_) async => canonical,
          send: (_, _) async {
            writes++;
            throw ApiException(409, 'Already applied', code: 'plan_conflict');
          },
          readStore: (_) async => jsonEncode({
            'data': {
              '/households/1/meal-plan': {'revision': 1, 'entries': []},
            },
            'queue': [queued],
          }),
          writeStore: (_, _) async {},
        );
        addTearDown(local.dispose);
        await local.synchronize();
        expect(writes, 1);
        expect(local.pending, 0);
        expect(local.conflicts, isEmpty);
        expect(
          (await local.cached('/households/1/meal-plan'))!['entries'],
          canonical['entries'],
        );
      },
    );
  }
  test(
    'restart preserves genuine conflicts and uncertain non-receipted creates',
    () async {
      var sends = 0;
      final local = LocalData(
        key: 'review',
        fetch: (_) async => {},
        send: (_, _) async {
          sends++;
          return {};
        },
        readStore: (_) async => jsonEncode({
          'data': {},
          'queue': [
            {
              'id': 'conflict',
              'path': '/households/1/meal-plan',
              'body': {'operation': 'move', 'id': 'a'},
              'problem': 'Choose a date',
              'problem_code': 'plan_conflict',
            },
            {
              'id': 'create',
              'path': '/households/1/recipes',
              'body': {'title': 'private'},
              'creating': true,
              'sending': true,
            },
          ],
        }),
        writeStore: (_, _) async {},
      );
      addTearDown(local.dispose);
      await local.synchronize();
      expect(sends, 0);
      expect(local.conflicts, hasLength(2));
      expect(local.pending, 2);
    },
  );
}
