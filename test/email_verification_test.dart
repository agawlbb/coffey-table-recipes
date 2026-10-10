import 'package:coffey_table_recipes/src/email_verification_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_design_test.dart' show TestUser;

class PendingUser extends TestUser {
  PendingUser(this.id, {this.fail = false});
  final String id;
  final bool fail;
  int sends = 0;
  @override
  String get uid => id;
  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    sends++;
    if (fail) throw FirebaseAuthException(code: 'network-request-failed');
  }
}

void main() {
  testWidgets(
    'verification sends automatically, resends, and checks completion',
    (tester) async {
      final user = PendingUser('verification-gate');
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: EmailVerificationScreen(
            user: user,
            refresh: () async {
              refreshes++;
            },
            signOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(user.sends, 1);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining(user.email!), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(find.text('I verified my email'), findsNothing);
      expect(find.text('Set up household'), findsNothing);
      await tester.tap(find.text('Resend verification email'));
      await tester.pumpAndSettle();
      expect(user.sends, 2);
      await tester.pump(const Duration(seconds: 5));
      expect(refreshes, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('send failure remains on verification screen with retry', (
    tester,
  ) async {
    final user = PendingUser('verification-failure', fail: true);
    await tester.pumpWidget(
      MaterialApp(
        home: EmailVerificationScreen(
          user: user,
          refresh: () async {},
          signOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be sent'), findsOneWidget);
    expect(find.text('Resend verification email'), findsOneWidget);
    await tester.tap(find.text('Resend verification email'));
    await tester.pumpAndSettle();
    expect(user.sends, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
