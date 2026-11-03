import 'dart:async';

import 'notification_preferences.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

final syncMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// OS reminders are scheduled on local persistence, independently of networking.
/// The in-app overdue status also works on web and when permission is denied.
class SyncNotifications {
  static const channel = MethodChannel('coffey_table_recipes/pending_saves');
  static final _latest = <String, List<Map<String, dynamic>>>{};
  static Future<void> replay() async {
    for (final entry in _latest.entries.toList()) {
      await update(entry.key, entry.value);
    }
  }

  static final _announced = <String>{};
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _notice;
  static Future<void> update(
    String scope,
    List<Map<String, dynamic>> changes,
  ) async {
    _latest[scope] = changes;
    final prefix = '$scope|';
    final ids = changes.map((q) => '$prefix${q['id']}').toSet();
    _announced.removeWhere((id) => id.startsWith(prefix) && !ids.contains(id));
    final due =
        (notificationPreferences.values['pendingSaves'] == false
                ? <Map<String, dynamic>>[]
                : changes)
            .where(
              (q) =>
                  (q['deadline'] as int) <=
                  DateTime.now().millisecondsSinceEpoch,
            )
            .toList();
    if (due.isEmpty) {
      _notice?.close();
      _notice = null;
    } else if (due.any((q) => !_announced.contains('$prefix${q['id']}')) &&
        syncMessengerKey.currentState != null) {
      _announced.addAll(due.map((q) => '$prefix${q['id']}'));
      _notice?.close();
      final notice = syncMessengerKey.currentState!.showSnackBar(
        SnackBar(
          content: const Text(
            'A change is saved on this device, but the server has not confirmed it after one minute.',
          ),
          duration: const Duration(seconds: 8),
          showCloseIcon: true,
        ),
      );
      _notice = notice;
      unawaited(
        notice.closed.then((_) {
          if (identical(_notice, notice)) _notice = null;
        }),
      );
    }
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
