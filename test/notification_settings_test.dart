import 'package:coffey_table_recipes/src/notification_preferences.dart';
import 'package:coffey_table_recipes/src/notification_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, bool> saved;
  late AuthorizationStatus status;
  late NotificationPreferences preferences;
  late List<MethodCall> calls;
  setUp(() {
    saved = {
      'invitations': true,
      'timers': true,
      'pendingSaves': true,
      'updates': true,
    };
    status = AuthorizationStatus.authorized;
    calls = [];
    preferences = NotificationPreferences(
      authorization: () async => status,
      requestAuthorization: () async {
        status = AuthorizationStatus.authorized;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationPreferences.channel, (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'read') {
            return {...saved, 'blockedChannels': <String>[]};
          }
          if (call.method == 'set') {
            saved[call.arguments['category'] as String] =
                call.arguments['enabled'] as bool;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationPreferences.channel, null);
  });
  test('permission is requested only while undetermined, preserving denied and granted decisions', () async {
    var requests = 0;
    preferences = NotificationPreferences(
      authorization: () async => status,
      requestAuthorization: () async {
        requests++;
        status = AuthorizationStatus.authorized;
      },
    );
    status = AuthorizationStatus.notDetermined;
    await preferences.requestOnFirstLaunch();
    expect(requests, 1);
    await preferences.requestOnFirstLaunch();
    expect(requests, 1);
    status = AuthorizationStatus.denied;
    await preferences.requestOnFirstLaunch();
    expect(requests, 1);
    expect(preferences.allowed, isFalse);
  });
  test(
    'category choices survive permission changes and independent updates',
    () async {
      await preferences.read();
      await preferences.set('invitations', false);
      status = AuthorizationStatus.denied;
      await preferences.read();
      expect(preferences.values['invitations'], isFalse);
      expect(preferences.values['timers'], isTrue);
      expect(preferences.allowed, isFalse);
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'category screen and native settings links fit a narrow phone: $platform',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: NotificationSettingsScreen(
              preferences: preferences,
              saveInvitations: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(Switch),
          findsNWidgets(platform == TargetPlatform.android ? 3 : 2),
        );
        expect(find.text('Pending saves'), findsNothing);
        expect(
          find.text('App updates'),
          platform == TargetPlatform.android ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Phone notification settings'));
        await tester.pumpAndSettle();
        expect(calls.last.method, 'openSettings');
        if (platform == TargetPlatform.android) {
          await tester.tap(
            find.byTooltip('Cooking invitations phone settings'),
          );
          await tester.pumpAndSettle();
          expect(calls.last.arguments['category'], 'invitations');
        }
        await tester.tap(find.byType(Switch).at(1));
        await tester.pumpAndSettle();
        expect(saved['timers'], isFalse);
        expect(saved['invitations'], isTrue);
        status = AuthorizationStatus.denied;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('Not allowed'), findsOneWidget);
        expect(saved['timers'], isFalse);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
  testWidgets(
    'failed server preference leaves invitations enabled and reports the failed action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            preferences: preferences,
            saveInvitations: (_) async => throw StateError('offline'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(saved['invitations'], isTrue);
      expect(calls.where((call) => call.method == 'set'), isEmpty);
      expect(
        find.text('Could not update notification settings. Please try again.'),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'invitation choice is confirmed by the server before local opt-out',
    (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            preferences: preferences,
            saveInvitations: (enabled) async {
              expect(saved['invitations'], isTrue);
              expect(enabled, isFalse);
              confirmed = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
      expect(saved['invitations'], isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'enabling timer alerts explains missing alarm permission without changing the choice',
    (tester) async {
      saved['timers'] = false;
      const timerChannel = MethodChannel('coffey_table_recipes/timers');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            timerChannel,
            (_) async => throw PlatformException(
              code: 'permission',
              message: 'Allow alarms in Settings, then try again.',
            ),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(timerChannel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            preferences: preferences,
            saveInvitations: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(saved['timers'], isFalse);
      expect(
        find.text('Allow alarms in Settings, then try again.'),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
