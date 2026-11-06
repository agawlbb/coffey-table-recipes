import 'dart:convert';

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
}
