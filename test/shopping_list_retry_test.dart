import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shopping_list_cache_test.dart' show memoryCache, screen, snapshot;

void main() {
  testWidgets(
    'failed reads keep the cache and wait for an explicit refresh or connection event',
    (tester) async {
      final cache = memoryCache(<String, String>{});
      await cache.save(snapshot(1, 'Cached milk'));
      var connected = false, reads = 0;
      await tester.pumpWidget(
        screen(cache, (path, {body}) async {
          reads++;
          if (!connected) throw TimeoutException('offline');
          return snapshot(2, 'Fresh milk');
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cached milk'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(reads, 1);
      connected = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh milk'), findsOneWidget);
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
