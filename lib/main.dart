import 'package:firebase_auth/firebase_auth.dart';

import 'src/child_mode.dart';
import 'src/offline_store.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'src/app.dart';
import 'src/shared_recipe_import.dart';
import 'src/firebase_config.dart';
import 'src/timer_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await sharedRecipeInbox.start();
  final options = FirebaseConfig.options;
  String? initializationError;
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
    } catch (_) {
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
      await timerSync.start();
    } catch (_) {
      timerSync.status.value =
          'Timer sharing could not start. Reopen the app to try again.';
    }
  }
  runApp(
    CoffeyTableApp(
      authConfigured: options != null && initializationError == null,
      initializationError: initializationError,
    ),
  );
}
