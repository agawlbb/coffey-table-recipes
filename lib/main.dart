import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'src/app.dart';
import 'src/debug_host.dart';
import 'src/firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadDebugApiOverride();
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
  runApp(
    CoffeyTableApp(
      authConfigured: options != null && initializationError == null,
      initializationError: initializationError,
    ),
  );
}
