import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

class NotificationPreferences {
  NotificationPreferences({this.authorization, this.requestAuthorization});
  static const channel = MethodChannel('coffey_table_recipes/notifications');
  final Future<AuthorizationStatus> Function()? authorization;
  final Future<void> Function()? requestAuthorization;
  Map<String, bool> values = {};
  Set<String> blockedChannels = {};
  AuthorizationStatus status = AuthorizationStatus.notDetermined;

  Future<void> read() async {
    final data = await channel.invokeMapMethod<String, dynamic>('read') ?? {};
    values = {
      for (final key in ['invitations', 'timers', 'pendingSaves', 'updates'])
        key: data[key] as bool? ?? true,
    };
    blockedChannels = (data['blockedChannels'] as List? ?? [])
        .cast<String>()
        .toSet();
    status =
        await (authorization?.call() ??
            FirebaseMessaging.instance.getNotificationSettings().then(
              (value) => value.authorizationStatus,
            ));
  }

  bool get allowed =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  Future<void> requestOnFirstLaunch() async {
    await read();
    if (status != AuthorizationStatus.notDetermined) return;
    await (requestAuthorization?.call() ??
        FirebaseMessaging.instance.requestPermission());
    await read();
  }

  Future<void> set(String category, bool enabled) async {
    await channel.invokeMethod<void>('set', {
      'category': category,
      'enabled': enabled,
    });
    values[category] = enabled;
  }

  Future<void> openSettings([String? category]) =>
      channel.invokeMethod<void>('openSettings', {'category': category});
}

final notificationPreferences = NotificationPreferences();
