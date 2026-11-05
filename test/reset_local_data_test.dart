import 'dart:io';

import 'package:coffey_table_recipes/src/offline_store_io.dart';
import 'package:coffey_table_recipes/src/reset_local_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('update clears recipe caches and pending actions once, preserving login and device settings', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    await preferences.setString('cooking_outbox_alice', '[pending]');
    await preferences.setString('timer_installation', 'existing-device');
    await preferences.setString('notification_preference', 'enabled');
    var clears = 0;
    await resetLocalDataForUpdate(
      preferences: preferences,
      clearData: () async {
        clears++;
      },
    );
    expect(await preferences.getString('cooking_outbox_alice'), isNull);
    expect(
      await preferences.getString('timer_installation'),
      'existing-device',
    );
    expect(await preferences.getString('notification_preference'), 'enabled');
    await resetLocalDataForUpdate(
      preferences: preferences,
      clearData: () async {
        clears++;
      },
    );
    expect(clears, 1);
  });
  test('cache reset removes owned recipe files without touching other application files', () async {
    final directory = await Directory.systemTemp.createTemp('ctr-reset-');
    addTearDown(() => directory.delete(recursive: true));
    final store = OfflineFileStore(directory: () async => directory);
    await store.write('local-first-v1-account', 'pending recipes');
    await store.write('public-recipes', 'cached recipe');
    final authentication = File('${directory.path}/authentication');
    await authentication.writeAsString('existing login');
    await store.clear();
    expect(await store.read('local-first-v1-account'), isNull);
    expect(await store.read('public-recipes'), isNull);
    expect(await authentication.readAsString(), 'existing login');
  });
}
