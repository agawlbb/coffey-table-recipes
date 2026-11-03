import 'package:coffey_table_recipes/src/android_release_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android subscribes to release announcements without owning permission requests', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    expect(
      await registerAndroidReleaseNotifications(
        subscribeToTopic: (topic) async => calls.add(topic),
      ),
      isTrue,
    );
    expect(calls, ['android_releases']);
  });

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
        await registerAndroidReleaseNotifications(subscribeToTopic: subscribe),
        isFalse,
      );
      online = true;
      expect(
        await registerAndroidReleaseNotifications(subscribeToTopic: subscribe),
        isTrue,
      );
      expect(subscriptions, 2);
    },
  );

  test(
    'unavailable subscription API does not escape into app startup',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var subscriptions = 0;
      expect(
        await registerAndroidReleaseNotifications(
          subscribeToTopic: (_) async {
            subscriptions++;
            throw StateError('unavailable');
          },
        ),
        isFalse,
      );
      expect(subscriptions, 1);
    },
  );

  test(
    'other platforms never request permissions or register the topic',
    () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = platform;
        var calls = 0;
        expect(
          await registerAndroidReleaseNotifications(
            subscribeToTopic: (_) async => calls++,
          ),
          isFalse,
        );
        expect(calls, 0);
      }
    },
  );
}
