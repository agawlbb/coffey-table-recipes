import 'package:coffey_table_recipes/src/email_verification_screen.dart';
import 'package:coffey_table_recipes/src/invitation_entry.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_design_test.dart' show TestUser;

class PendingUser extends TestUser {
  PendingUser(this.id, {this.fail = false, this.errorCode});
  final String id;
  final bool fail;
  final String? errorCode;
  int sends = 0;
  @override
  String get uid => id;
  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    sends++;
    if (errorCode != null) throw FirebaseAuthException(code: errorCode!);
    if (fail) throw FirebaseAuthException(code: 'network-request-failed');
  }
}

void main() {
  testWidgets(
    'Firebase limit reports rejection without inventing a reset time',
    (tester) async {
      final user = PendingUser(
        'rate-limit-message',
        errorCode: 'too-many-requests',
      );
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
      await tester.tap(find.text('Resend verification email'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not provide a retry time'),
        findsOneWidget,
      );
      expect(find.textContaining('few minutes'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(user.sends, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unverified account registers once without sending email', (
    tester,
  ) async {
    final user = PendingUser('registration-before-verification');
    var registrations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EmailVerificationScreen(
          user: user,
          refresh: () async {},
          signOut: () async {},
          registerAccount: () async {
            registrations++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(registrations, 1);
    expect(user.sends, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signup send failure is visible without sending again', (
    tester,
  ) async {
    final user = PendingUser('signup-send-failure', fail: true);
    await InvitationVerification.send(user).catchError((Object _) {});
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
    expect(user.sends, 1);
    expect(find.textContaining('could not be sent'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(user.sends, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'verification opens without sending; explicit resend sends once',
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
      expect(user.sends, 0);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining(user.email!), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(find.text('I verified my email'), findsNothing);
      expect(find.text('Set up household'), findsNothing);
      await tester.tap(find.text('Resend verification email'));
      await tester.pumpAndSettle();
      expect(user.sends, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(refreshes, greaterThanOrEqualTo(2));
      expect(user.sends, 1);
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
    expect(user.sends, 0);
    expect(find.textContaining('could not be sent'), findsNothing);
    expect(find.text('Resend verification email'), findsOneWidget);
    await tester.tap(find.text('Resend verification email'));
    await tester.pumpAndSettle();
    expect(user.sends, 1);
    expect(find.textContaining('could not be sent'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
