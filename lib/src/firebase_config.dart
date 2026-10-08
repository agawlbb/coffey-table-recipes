import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class FirebaseConfig {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static FirebaseOptions? get options {
    final String appId;
    final String apiKey;
    if (kIsWeb) {
      appId = const String.fromEnvironment('FIREBASE_WEB_APP_ID');
      apiKey = const String.fromEnvironment('FIREBASE_WEB_API_KEY');
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      appId = const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
      apiKey = const String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      appId = const String.fromEnvironment('FIREBASE_IOS_APP_ID');
      apiKey = const String.fromEnvironment('FIREBASE_IOS_API_KEY');
    } else {
      return null;
    }
    if (projectId.isEmpty || appId.isEmpty || apiKey.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: const String.fromEnvironment('FIREBASE_SENDER_ID'),
      projectId: projectId,
      authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      iosClientId: const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
      iosBundleId: 'com.coffeytable.coffeyTableRecipes',
    );
  }
}
