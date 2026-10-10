import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class InvitationEntry {
  InvitationEntry(Uri uri)
    : email = uri.queryParameters['email'] ?? '',
      register = uri.queryParameters['account'] == 'create',
      signIn = uri.queryParameters['account'] == 'signin';
  final String email;
  final bool register;
  final bool signIn;

  static String verificationReturnUrl(String email) =>
      Uri.parse('https://coffeybean.com/CoffeyTableRecipes/app/')
          .replace(queryParameters: {'account': 'signin', 'email': email})
          .toString();
}

abstract final class InvitationVerification {
  static final Map<String, Future<void>> _sent = {};
  static final Map<String, Future<void>> _attempts = {};
  static final ValueNotifier<int> changes = ValueNotifier(0);
  // Observe an existing signup attempt without making a new send request.
  static Future<void>? attemptFor(String uid) => _attempts[uid];
  static Future<void> send(User user, {bool resend = false}) {
    if (resend) _sent.remove(user.uid);
    final attempt = _sent.putIfAbsent(user.uid, () async {
      try {
        try {
          await user.sendEmailVerification(
            ActionCodeSettings(
              url: InvitationEntry.verificationReturnUrl(user.email ?? ''),
              handleCodeInApp: false,
            ),
          );
        } on FirebaseAuthException catch (error) {
          if (error.code != 'unauthorized-continue-uri') rethrow;
          // Verification can still proceed when the optional return URL is not
          // authorized. Keep Firebase's hosted verification link functional.
          await user.sendEmailVerification();
        }
      } catch (_) {
        _sent.remove(user.uid);
        rethrow;
      }
    });
    _attempts[user.uid] = attempt;
    changes.value++;
    return attempt;
  }
}
