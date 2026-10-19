import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:coffey_table_recipes/src/shopping_list_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> snapshot(int revision, String name) => {
  'revision': revision,
  'departments': ['Produce', 'Dairy'],
  'items': [
    {'id': 'item', 'name': name, 'checked': true, 'department': 'Dairy'},
  ],
};
ShoppingListCache memoryCache(
  Map<String, String> disk, {
  String account = 'u1',
  String household = 'h1',
}) => ShoppingListCache(
  account: account,
  household: household,
  server: 'https://example.test',
  readStore: (key) async => disk[key],
  writeStore: (key, value) async {
    disk[key] = value;
  },
);
Widget screen(
  ShoppingListCache cache,
  ShoppingRequest request, {
  bool active = true,
}) => MaterialApp(
  home: ShoppingListScreen(
    householdId: 'h1',
    householdName: 'Our table',
    cache: cache,
    request: request,
    active: active,
  ),
);

void main() {
  test(
    'cache is scoped and handles malformed or unavailable storage',
    () async {
      final disk = <String, String>{};
      final cache = memoryCache(disk);
      await cache.save(snapshot(2, 'Milk'));
      expect((await memoryCache(disk).read())!['revision'], 2);
      expect(await memoryCache(disk, account: 'another-user').read(), isNull);
      expect(
        await memoryCache(disk, household: 'another-household').read(),
        isNull,
      );
      final otherServer = ShoppingListCache(
        account: 'u1',
        household: 'h1',
        server: 'https://another.test',
        readStore: (key) async => disk[key],
      );
      expect(await otherServer.read(), isNull);
      disk[cache.key] = 'not json';
      expect(await cache.read(), isNull);
      disk[cache.key] = jsonEncode({
        'revision': 2,
        'items': [
          {'id': 'broken'},
        ],
        'departments': ['Produce'],
      });
      expect(await cache.read(), isNull);
      final blocked = ShoppingListCache(
        account: 'blocked',
        household: 'h1',
        server: 'test',
        readStore: (_) async => throw Exception('unavailable'),
        writeStore: (_, _) async => throw Exception('quota'),
      );
      expect(await blocked.read(), isNull);
      await blocked.save(snapshot(2, 'Milk'));
      await blocked.clear();
    },
  );

  testWidgets(
    'stationary mouse and touch holds reveal empty departments without a checkbox',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final disk = <String, String>{};
      var items = <Map<String, dynamic>>[
        {'id': 'milk', 'name': 'Milk', 'department': 'Dairy', 'checked': false},
      ];
      var revision = 1;
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
      }) async {
        if (body != null) {
          revision++;
          items = (body['items'] as List).cast<Map<String, dynamic>>();
        }
        return {
          'revision': revision,
          'items': items,
          'departments': ['Produce', 'Dairy', 'Bakery'],
        };
      }

      await tester.pumpWidget(screen(memoryCache(disk), request));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Hide empty departments'), findsNothing);
      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        final target = items.single['department'] == 'Dairy'
            ? 'Bakery'
            : 'Dairy';
        expect(find.text(target), findsNothing);
        final cancelled = await tester.startGesture(
          tester.getCenter(find.text('Milk')),
          kind: kind,
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text(target), findsOneWidget);
        expect(find.text('Produce'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Produce')).dy,
          lessThan(tester.getTopLeft(find.text('Dairy')).dy),
        );
        await cancelled.cancel();
        await tester.pumpAndSettle();
        expect(find.text(target), findsNothing);
        final released = await tester.startGesture(
          tester.getCenter(find.text('Milk')),
          kind: kind,
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text(target), findsOneWidget);
        await released.up();
        await tester.pumpAndSettle();
        expect(items.single['checked'], false);
        expect(find.text(target), findsNothing);
        final drag = await tester.startGesture(
          tester.getCenter(find.text('Milk')),
          kind: kind,
        );
        await tester.pump(const Duration(milliseconds: 600));
        await drag.moveTo(
          tester.getCenter(find.byKey(ValueKey('department-$target'))),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await drag.up();
        await tester.pumpAndSettle();
        expect(items.single['department'], target);
        expect(items.single['checked'], false);
        expect(find.text('Produce'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(memoryCache(disk), request));
      await tester.pumpAndSettle();
      expect(find.text('Produce'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cached list appears while opening refresh waits and updated list survives reopening',
    (tester) async {
      final disk = <String, String>{};
      final cache = memoryCache(disk);
      await cache.save(snapshot(2, 'Cached milk'));
      final opening = Completer<Map<String, dynamic>>();
      var reads = 0;
      await tester.pumpWidget(
        screen(cache, (path, {body}) {
          reads++;
          return opening.future;
        }),
      );
      await tester.pump();
      expect(reads, 1);
      expect(find.text('Cached milk'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Cached milk')).style?.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      opening.complete(snapshot(3, 'Fresh milk'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh milk'), findsOneWidget);
      expect(find.text('Cached milk'), findsNothing);
      expect((await cache.read())!['revision'], 3);
      await tester.pumpWidget(const SizedBox());
      final reopen = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        screen(memoryCache(disk), (path, {body}) {
          reads++;
          return reopen.future;
        }),
      );
      await tester.pump();
      expect(reads, 2);
      expect(find.text('Fresh milk'), findsOneWidget);
      reopen.complete(snapshot(3, 'Fresh milk'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'offline cache stays visible and five-second polling recovers without losing typed text',
    (tester) async {
      final cache = memoryCache(<String, String>{});
      await cache.save(snapshot(2, 'Milk'));
      var reads = 0;
      var connected = false;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, value, _) => screen(cache, (path, {body}) async {
            reads++;
            if (!connected) throw TimeoutException('offline');
            return snapshot(2, 'Milk');
          }, active: value),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Offline'), findsOneWidget);
      expect(find.byTooltip('No server connection'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Add item',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Keep my draft');
      expect(reads, 3);
      connected = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(reads, 4);
      expect(find.text('Offline'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep my draft',
      );
      active.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      expect(reads, 4);
      active.value = true;
      await tester.pumpAndSettle();
      expect(reads, 5);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 10));
      expect(reads, 5);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reads, 6);
      final navigator = Navigator.of(
        tester.element(find.byType(ShoppingListScreen)),
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Another view')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(reads, 6);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(reads, 7);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a late cache read cannot replace the latest server response', (
    tester,
  ) async {
    final late = Completer<String?>();
    final cache = ShoppingListCache(
      account: 'late',
      household: 'h1',
      server: 'test',
      readStore: (_) => late.future,
      writeStore: (_, _) async {},
    );
    await tester.pumpWidget(
      screen(cache, (path, {body}) async => snapshot(3, 'Fresh milk')),
    );
    await tester.pumpAndSettle();
    late.complete(jsonEncode(snapshot(1, 'Stale milk')));
    await tester.pumpAndSettle();
    expect(find.text('Fresh milk'), findsOneWidget);
    expect(find.text('Stale milk'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed edits do not replace the confirmed cache', (
    tester,
  ) async {
    final cache = memoryCache(<String, String>{});
    await tester.pumpWidget(
      screen(cache, (path, {body}) async {
        if (body != null) throw TimeoutException('offline');
        return snapshot(2, 'Milk');
      }),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved item');
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget);
    final saved = await cache.read();
    expect((saved!['items'] as List).single['name'], 'Milk');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Unsaved item',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('access denial clears cached household data', (tester) async {
    final cache = memoryCache(<String, String>{});
    await cache.save(snapshot(2, 'Private milk'));
    final response = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(screen(cache, (path, {body}) => response.future));
    await tester.pump();
    expect(find.text('Private milk'), findsOneWidget);
    response.completeError(ApiException(403, 'Household access removed'));
    await tester.pumpAndSettle();
    expect(find.text('Private milk'), findsNothing);
    expect(find.text('Household access removed'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(await cache.read(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
