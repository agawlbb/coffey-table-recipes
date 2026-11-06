import 'src/reset_local_data.dart';
import 'src/client_log.dart';
import 'src/client_error_logging.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'src/child_mode.dart';
import 'src/offline_store.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'src/app.dart';
import 'src/android_release_notifications.dart';
import 'src/shared_recipe_import.dart';
import 'src/firebase_config.dart';
import 'src/cooking_sessions.dart';
import 'src/notification_preferences.dart';
import 'src/native_timers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await resetLocalDataForUpdate();
  installClientErrorLogging();
  await clientLog.start();
  try {
    final info = await PackageInfo.fromPlatform().timeout(
      const Duration(seconds: 2),
    );
    clientLog.version = '${info.version}.${info.buildNumber}';
  } catch (error, stack) {
    clientLog.record('app', 'version_unavailable', error: error, stack: stack);
  }
  await sharedRecipeInbox.start();
  final options = FirebaseConfig.options;
  String? initializationError;
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
    } catch (error, stack) {
      clientLog.record(
        'startup',
        'firebase_failed',
        error: error,
        stack: stack,
      );
      initializationError =
          'Google sign-in could not start. Please reopen the app.';
    }
  }
  if (options != null && initializationError == null) {
    final account = FirebaseAuth.instance.currentUser;
    if (account != null) {
      try {
        childMode.value =
            await readOfflineStore('ctr-child-mode:${account.uid}')
                .timeout(const Duration(seconds: 2)) ==
            'true';
      } catch (_) {
        childMode.value = true;
      }
    }
    // Sharing failures must never prevent the app or local timers from starting.
    try {
      await cookingSessions.start();
    } catch (error, stack) {
      clientLog.record('startup', 'cooking_failed', error: error, stack: stack);
      cookingSessions.error =
          'Cooking sync could not start. Reopen the app to try again.';
    }
  }
  if (NativeTimers.supported &&
      options != null &&
      initializationError == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(() async {
        try {
          await notificationPreferences.requestOnFirstLaunch();
          await cookingSessions.refreshDeviceRegistration();
        } catch (_) {
          /* Permission and push availability never block startup. */
        }
        await registerAndroidReleaseNotifications();
      }());
    });
  }
  runApp(
    CoffeyTableApp(
      authConfigured: options != null && initializationError == null,
      initializationError: initializationError,
    ),
  );
}
