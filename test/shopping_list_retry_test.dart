import 'dart:async';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shopping_list_cache_test.dart' show memoryCache, screen, snapshot;

void main() {
  testWidgets('opening a throttled list keeps cache and retries quietly', (
    tester,
  ) async {
    final cache = memoryCache(<String, String>{});
    await cache.save(snapshot(1, 'Cached milk'));
    var attempts = 0;
    await tester.pumpWidget(
      screen(cache, (path, {body}) async {
        if (++attempts < 2) {
          throw ApiException(
            429,
            'HTTP 429',
            retryAfter: const Duration(seconds: 30),
          );
        }
        return snapshot(2, 'Fresh milk');
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cached milk'), findsOneWidget);
    expect(find.textContaining('HTTP 429'), findsNothing);
    await tester.pump(const Duration(seconds: 29));
    expect(attempts, 1);
    expect(find.text('Offline'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Fresh milk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('persistent throttling has a quiet paused indicator', (
    tester,
  ) async {
    final cache = memoryCache(<String, String>{});
    await cache.save(snapshot(1, 'Cached milk'));
    await tester.pumpWidget(
      screen(cache, (path, {body}) async {
        throw ApiException(429, 'HTTP 429');
      }),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Updates paused'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(find.textContaining('HTTP'), findsNothing);
    expect(find.text('Cached milk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('brief refresh failures recover without a user alert', (
    tester,
  ) async {
    final cache = memoryCache(<String, String>{});
    await cache.save(snapshot(1, 'Cached milk'));
    var attempts = 0;
    await tester.pumpWidget(
      screen(cache, (path, {body}) async {
        if (++attempts < 3) {
          throw ApiException(
            502,
            'The recipe service could not complete the request',
          );
        }
        return snapshot(2, 'Fresh milk');
      }),
    );
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Cached milk'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(attempts, 2);
    expect(find.text('Offline'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(attempts, 3);
    expect(find.text('Fresh milk'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(find.textContaining('could not complete'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed save gets quiet retries and a neutral actionable notice',
    (tester) async {
      final cache = memoryCache(<String, String>{});
      var writes = 0;
      await tester.pumpWidget(
        screen(cache, (path, {body}) async {
          if (body != null) {
            writes++;
            throw ApiException(
              503,
              'The recipe service could not complete the request (HTTP 503)',
            );
          }
          return snapshot(1, 'Milk');
        }),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Eggs');
      await tester.tap(find.byTooltip('Add item'));
      await tester.pump();
      expect(writes, 1);
      expect(find.text('Offline'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(writes, 2);
      expect(find.textContaining("couldn't be saved"), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(writes, 3);
      final notice = find.text(
        "Your change couldn't be saved. Please try again when connected.",
      );
      expect(notice, findsOneWidget);
      expect(
        tester.widget<Text>(notice).style!.color,
        isNot(Theme.of(tester.element(notice)).colorScheme.error),
      );
      expect(find.textContaining('HTTP'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Eggs',
      );
      expect((await cache.read())!['revision'], 1);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final verificationFailsOnce in [false, true]) {
    testWidgets(
      'lost save response is reconciled, temporary verification failure: $verificationFailsOnce',
      (tester) async {
        final cache = memoryCache(<String, String>{});
        var revision = 0, writes = 0, commits = 0;
        var failVerification = verificationFailsOnce;
        var items = <Map<String, dynamic>>[];
        await tester.pumpWidget(
          screen(cache, (path, {body}) async {
            if (body != null) {
              writes++;
              if (body['revision'] != revision) {
                throw ApiException(409, 'The shopping list changed.');
              }
              items = [
                for (final value in body['items'] as List)
                  {
                    ...Map<String, dynamic>.from(value as Map),
                    'department': 'Produce',
                  },
              ];
              revision++;
              commits++;
              throw TimeoutException('response lost');
            }
            if (revision > 0 && failVerification) {
              failVerification = false;
              throw TimeoutException('verification temporarily unavailable');
            }
            return {
              'revision': revision,
              'items': items,
              'departments': ['Produce'],
            };
          }),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Apples');
        await tester.tap(find.byTooltip('Add item'));
        await tester.pumpAndSettle();
        expect(writes, verificationFailsOnce ? 3 : 2);
        expect(commits, 1);
        expect(items, hasLength(1));
        expect(find.text('Apples'), findsOneWidget);
        expect(find.text('Offline'), findsNothing);
        expect(find.textContaining("couldn't be saved"), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('real concurrent changes are not overwritten by a retry', (
    tester,
  ) async {
    final cache = memoryCache(<String, String>{});
    var revision = 0, writes = 0;
    var items = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      screen(cache, (path, {body}) async {
        if (body != null) {
          writes++;
          if (writes == 1) {
            items = [
              {
                'id': 'other',
                'name': 'Other member item',
                'department': '',
                'checked': false,
              },
            ];
            revision = 1;
            throw TimeoutException('connection lost');
          }
          throw ApiException(
            409,
            'The shopping list changed. Review it and try again.',
          );
        }
        return {
          'revision': revision,
          'items': items,
          'departments': ['Produce'],
        };
      }),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My item');
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(items.single['name'], 'Other member item');
    expect(find.text('Other member item'), findsOneWidget);
    expect(
      find.text('The shopping list changed. Review it and try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'My item',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving during a quiet retry cancels scheduled attempts', (
    tester,
  ) async {
    final cache = memoryCache(<String, String>{});
    await cache.save(snapshot(1, 'Milk'));
    var attempts = 0;
    await tester.pumpWidget(
      screen(cache, (path, {body}) async {
        attempts++;
        throw ApiException(503, 'Unavailable');
      }),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(attempts, 1);
    expect(tester.takeException(), isNull);
  });
}
