import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';

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
  @visibleForTesting
  static Future<void> Function(User) delivery = sendHosted;

  static Future<void> sendHosted(User user, {RecipeApi? api}) async {
    final service = api ?? RecipeApi(baseUrl: apiBaseUrl);
    try {
      final token = await user.getIdToken(true);
      if (token == null) throw ApiException(401, 'Please sign in again.');
      await service.request(
        '/me/verification-email',
        token,
        body: {},
        timeout: const Duration(seconds: 45),
      );
    } finally {
      if (api == null) service.close();
    }
  }

  static final Map<String, Future<void>> _sent = {};
  static final Map<String, Future<void>> _attempts = {};
  static final ValueNotifier<int> changes = ValueNotifier(0);
  // Observe an existing signup attempt without making a new send request.
  static Future<void>? attemptFor(String uid) => _attempts[uid];
  static Future<void> send(User user, {bool resend = false}) {
    if (resend) _sent.remove(user.uid);
    final attempt = _sent.putIfAbsent(user.uid, () async {
      try {
        await delivery(user);
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
