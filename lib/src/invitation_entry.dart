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
  static final Map<String, Future<void>> _inFlight = {};
  static final Map<String, DateTime> _resendAfter = {};
  static const resendCooldown = Duration(seconds: 60);
  @visibleForTesting
  static DateTime Function() now = DateTime.now;
  static Duration resendRemaining(String uid) {
    final deadline = _resendAfter[uid];
    final remaining = deadline?.difference(now()) ?? Duration.zero;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @visibleForTesting
  static void resetForTesting() {
    _sent.clear();
    _attempts.clear();
    _inFlight.clear();
    _resendAfter.clear();
    now = DateTime.now;
  }

  static final ValueNotifier<int> changes = ValueNotifier(0);
  // Observe an existing signup attempt without making a new send request.
  static Future<void>? attemptFor(String uid) => _attempts[uid];
  static Future<void> send(User user, {bool resend = false}) {
    final running = _inFlight[user.uid];
    if (running != null) return running;
    final previous = _sent[user.uid];
    if (!resend && previous != null) return previous;
    final remaining = resendRemaining(user.uid);
    if (remaining > Duration.zero) {
      return Future.error(
        ApiException(
          429,
          'Please wait before resending the verification email.',
          code: 'verification_cooldown',
          retryAfter: remaining,
        ),
      );
    }
    if (resend) _sent.remove(user.uid);
    final attempt = () async {
      try {
        await Future<void>.sync(() => delivery(user));
      } catch (_) {
        _sent.remove(user.uid);
        rethrow;
      } finally {
        _resendAfter[user.uid] = now().add(resendCooldown);
        _inFlight.remove(user.uid);
        changes.value++;
      }
    }();
    _sent[user.uid] = attempt;
    _inFlight[user.uid] = attempt;
    _attempts[user.uid] = attempt;
    changes.value++;
    return attempt;
  }
}
