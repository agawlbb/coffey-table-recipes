import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_config.dart';

abstract final class GoogleAuthentication {
  static Future<void>? _initialization;
  static Future<void> signIn() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      return;
    }
    _initialization ??= GoogleSignIn.instance.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID')
          : null,
      serverClientId: FirebaseConfig.serverClientId.isEmpty
          ? null
          : FirebaseConfig.serverClientId,
    );
    await _initialization;
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google did not return a sign-in credential.');
    }
    await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  static Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb && _initialization != null) {
      await GoogleSignIn.instance.signOut();
    }
  }

  static String message(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'popup-closed-by-user' || 'cancelled-popup-request' =>
          'Sign-in was cancelled. You can try again.',
        'popup-blocked' => 'Allow the Google sign-in popup, then try again.',
        'network-request-failed' =>
          'Check your internet connection and try again.',
        'unauthorized-domain' =>
          'This web address is not enabled for Google sign-in yet.',
        'user-disabled' => 'This Google account cannot access the app.',
        _ => 'Google sign-in could not be completed. Please try again.',
      };
    }
    if (error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.canceled) {
      return 'Sign-in was cancelled. You can try again.';
    }
    return 'Google sign-in could not be completed. Please try again.';
  }
}
