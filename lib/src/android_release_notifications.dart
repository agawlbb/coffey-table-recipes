import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Release announcements are independent of sign-in and timer sharing.
/// Registration is best effort and retries on the next app launch.
Future<bool> registerAndroidReleaseNotifications({
  Future<void> Function()? requestPermission,
  Future<void> Function(String topic)? subscribeToTopic,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    await (requestPermission?.call() ??
        FirebaseMessaging.instance.requestPermission());
    await (subscribeToTopic?.call('android_releases') ??
        FirebaseMessaging.instance.subscribeToTopic('android_releases'));
    return true;
  } catch (_) {
    // An offline device or unavailable Firebase must never delay app startup.
    return false;
  }
}
