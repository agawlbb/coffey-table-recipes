import 'native_timers.dart';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_store.dart';

// One requested reset for this update, before any recipe/session cache is read.
Future<void> resetLocalDataForUpdate({
  SharedPreferencesAsync? preferences,
  Future<void> Function()? clearData,
}) async {
  final prefs = preferences ?? SharedPreferencesAsync();
  const marker = 'server-reload-2.7.6';
  if (await prefs.getBool(marker) == true) return;
  if (clearData != null) {
    await clearData();
  } else {
    await clearOfflineStore();
    await DefaultCacheManager().emptyCache();
    if (NativeTimers.supported) {
      await NativeTimers.channel.invokeMethod<void>('resetSyncCache');
    }
  }
  for (final key in await prefs.getKeys()) {
    if (key.startsWith('cooking_outbox_')) await prefs.remove(key);
  }
  await prefs.setBool(marker, true);
}
