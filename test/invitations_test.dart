import 'dart:async';

import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/invitation_dialogs.dart';
import 'package:coffey_table_recipes/src/invitation_entry.dart';
import 'package:coffey_table_recipes/src/email_access.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_design_test.dart' show TestUser;

class VerificationUser extends TestUser {
  ActionCodeSettings? settings;
  int sends = 0;
  @override
  String get uid => 'verification-test';
  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    sends++;
    settings = actionCodeSettings;
  }
}

void main() {
  testWidgets('invitation entry selects signup and prefills email', (
    tester,
  ) async {
    final entry = InvitationEntry(
      Uri.parse(
        'https://coffeybean.com/CoffeyTableRecipes/app/?account=create&email=val%2Btest%40example.test',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmailAccess(
            initialEmail: entry.email,
            register: entry.register,
          ),
        ),
      ),
    );
    expect(find.widgetWithText(TextFormField, 'Your name'), findsOneWidget);
    expect(find.text('val+test@example.test'), findsOneWidget);
    final returned = InvitationEntry(
      Uri.parse(InvitationEntry.verificationReturnUrl(entry.email)),
    );
    expect(returned.signIn, isTrue);
    expect(returned.register, isFalse);
    expect(returned.email, entry.email);
  });
  testWidgets('accept failure stays visible and retry cannot submit twice', (
    tester,
  ) async {
    var attempts = 0;
    final completed = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Review'),
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => InvitationResponseDialog(
                  invitation: const {
                    'id': '7',
                    'household_name': 'Family',
                    'inviter_name': 'Alex',
                  },
                  respond: (_) async {
                    attempts++;
                    if (attempts == 1) {
                      throw ApiException(503, 'Please try again.');
                    }
                    await completed.future;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Please try again.'), findsOneWidget);
    expect(find.text('Household invitation'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Decline'))
          .onPressed,
      isNull,
    );
    expect(attempts, 2);
    completed.complete();
    await tester.pumpAndSettle();
    expect(find.text('Household invitation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'email dialog validates, shows rejection, and retries successfully',
    (tester) async {
      final emails = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Invite'),
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => InvitePersonDialog(
                    personName: 'Sam',
                    send: (email) async {
                      emails.add(email);
                      if (emails.length == 1) {
                        throw ApiException(
                          409,
                          'This person could not be invited because their account already belongs to a household.',
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'invalid');
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(emails, isEmpty);
      await tester.enterText(find.byType(TextFormField), ' sam@example.test ');
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be invited'), findsOneWidget);
      expect(find.text('Invite Sam'), findsOneWidget);
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
      expect(emails, ['sam@example.test', 'sam@example.test']);
      expect(find.text('Invite Sam'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final decision in ['Accept', 'Decline']) {
    testWidgets('pending invitation appears at login and supports $decision', (
      tester,
    ) async {
      String? response;
      var pending = true;
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
      }) async {
        if (path == '/me') {
          return {
            'households': response == 'accept'
                ? [
                    {'id': '2', 'name': 'Family', 'role': 'member'},
                  ]
                : [],
            'invitations': pending
                ? [
                    {
                      'id': '7',
                      'household_id': '2',
                      'household_name': 'Family',
                      'inviter_name': 'Alex',
                    },
                  ]
                : [],
          };
        }
        if (path == '/invitations/7/respond') {
          response = body!['decision'] as String;
          pending = false;
          return {
            'invitation': {
              'id': '7',
              'status': response == 'accept' ? 'accepted' : 'declined',
            },
          };
        }
        if (path.endsWith('/people')) return {'people': []};
        return {
          'recipes': [
            {'id': '8', 'title': 'Shared soup'},
          ],
          'next_offset': null,
        };
      }

      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(user: TestUser(), request: request),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Household invitation'), findsOneWidget);
      expect(find.text('Alex has invited you to join Family.'), findsOneWidget);
      await tester.tap(find.text(decision));
      await tester.pumpAndSettle();
      expect(response, decision.toLowerCase());
      expect(find.text('Household invitation'), findsNothing);
      expect(
        find.text('Shared soup'),
        decision == 'Accept' ? findsOneWidget : findsNothing,
      );
      if (decision == 'Decline') {
        expect(find.text('Set up household'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unverified invitee is prompted to verify before membership', (
    tester,
  ) async {
    final user = VerificationUser();
    await tester.pumpWidget(
      MaterialApp(
        home: HouseholdPanel(
          user: user,
          request: (path, {body}) async => {
            'households': [],
            'invitations': [],
            'invitation_verification_required': true,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You have a household invitation'), findsOneWidget);
    expect(find.text('Resend verification email'), findsOneWidget);
    expect(user.sends, 1);
    expect(Uri.parse(user.settings!.url).queryParameters['email'], user.email);
    expect(find.textContaining('Verification email sent.'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

