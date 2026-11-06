import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'offline_recipes.dart';
import 'app_connection.dart';

Future<void> connectionNotice(BuildContext context, String action) async {
  if (!offlineStatus.value) return;
  var unavailable = false;
  try {
    final values = await Connectivity().checkConnectivity();
    unavailable = values.every((v) => v == ConnectivityResult.none);
  } catch (_) {
    /* A failed check does not establish that the network is down. */
  }
  if (!context.mounted) return;
  final reason = unavailable
      ? 'You’re offline.'
      : appConnection.connecting
      ? 'Reconnecting to the server.'
      : 'We can’t reach the server right now.';
  final detail = action == 'shopping'
      ? 'You can use the list offline. Changes will sync when connected; removals are kept for two hours.'
      : action == 'add'
      ? 'A new recipe will be saved on this device and uploaded when you reconnect.'
      : 'Recipe edits will be saved on this device. We’ll ask before sending them when you reconnect.';
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$reason $detail')));
}
