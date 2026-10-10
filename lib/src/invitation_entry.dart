import 'package:firebase_auth/firebase_auth.dart';

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
  static Future<void> send(User user, {bool resend = false}) {
    if (resend) _sent.remove(user.uid);
    return _sent.putIfAbsent(user.uid, () async {
      try {
        await user.sendEmailVerification(
          ActionCodeSettings(
            url: InvitationEntry.verificationReturnUrl(user.email ?? ''),
            handleCodeInApp: false,
          ),
        );
      } catch (_) {
        _sent.remove(user.uid);
        rethrow;
      }
    });
  }
}
