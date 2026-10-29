import 'package:coffey_table_recipes/src/android_release_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Android requests permission and subscribes to release announcements',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <String>[];
      expect(
        await registerAndroidReleaseNotifications(
          requestPermission: () async => calls.add('permission'),
          subscribeToTopic: (topic) async => calls.add(topic),
        ),
        isTrue,
      );
      expect(calls, ['permission', 'android_releases']);
    },
  );

  test(
    'failed registration stays nonfatal and can retry on the next launch',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var online = false;
      var subscriptions = 0;
      Future<void> subscribe(String topic) async {
        subscriptions++;
        if (!online) throw StateError('offline');
      }

      expect(
        await registerAndroidReleaseNotifications(
          requestPermission: () async {},
          subscribeToTopic: subscribe,
        ),
        isFalse,
      );
      online = true;
      expect(
        await registerAndroidReleaseNotifications(
          requestPermission: () async {},
          subscribeToTopic: subscribe,
        ),
        isTrue,
      );
      expect(subscriptions, 2);
    },
  );

  test('unavailable permission API does not escape into app startup', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var subscriptions = 0;
    expect(
      await registerAndroidReleaseNotifications(
        requestPermission: () async => throw StateError('unavailable'),
        subscribeToTopic: (_) async => subscriptions++,
      ),
      isFalse,
    );
    expect(subscriptions, 0);
  });

  test(
    'other platforms never request permissions or register the topic',
    () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = platform;
        var calls = 0;
        expect(
          await registerAndroidReleaseNotifications(
            requestPermission: () async => calls++,
            subscribeToTopic: (_) async => calls++,
          ),
          isFalse,
        );
        expect(calls, 0);
      }
    },
  );
}
