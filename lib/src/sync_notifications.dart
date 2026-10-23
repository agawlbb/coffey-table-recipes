import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// OS reminders are scheduled on local persistence, independently of networking.
/// The in-app overdue status also works on web and when permission is denied.
class SyncNotifications {
  static const channel = MethodChannel('coffey_table_recipes/pending_saves');
  static Future<void> update(
    String scope,
    List<Map<String, dynamic>> changes,
  ) async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    await channel.invokeMethod<void>('update', {
      'scope': scope,
      'changes': changes,
    });
  }
}
