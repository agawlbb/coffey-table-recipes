import 'package:coffey_table_recipes/src/administration.dart';
import 'package:coffey_table_recipes/src/account_panel.dart';

import 'home_design_test.dart' show TestUser;

import 'package:coffey_table_recipes/src/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Firebase-only deletion uses UID after confirmation', (
    tester,
  ) async {
    final writes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AdministrationPage(
          request: (path, {body}) async {
            if (path == '/me') {
              return {
                'user': {'id': '1', 'account_role': 'administrator'},
              };
            }
            if (path == '/admin/users') {
              return {
                'users': writes.isEmpty
                    ? [
                        {
                          'id': 'firebase:orphan',
                          'firebase_uid': 'orphan',
                          'firebase_only': true,
                          'email': 'orphan@example.test',
                          'account_role': 'user',
                        },
                      ]
                    : [],
              };
            }
            expect(body, {'confirm': true});
            writes.add(path);
            return {'deleted': true};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete user'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(writes, ['/admin/firebase/orphan/delete']);
  });

  for (final person in [true, false]) {
    testWidgets(
      person
          ? 'delete unlinked person without account request'
          : 'delete own administrator account',
      (tester) async {
        final writes = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: AdministrationPage(
              request: (path, {body}) async {
                if (path == '/me') {
                  return {
                    'user': {'id': '1', 'account_role': 'administrator'},
                  };
                }
                if (path == '/admin/users') {
                  return {
                    'users': person
                        ? []
                        : [
                            {
                              'id': '1',
                              'display_name': 'Admin',
                              'account_role': 'administrator',
                            },
                          ],
                    'people': person && writes.isEmpty
                        ? [
                            {
                              'id': '1',
                              'display_name': 'Guest',
                              'household_name': 'Coffey',
                            },
                          ]
                        : [],
                  };
                }
                expect(body, {'confirm': true});
                writes.add(path);
                return {'deleted': true};
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byTooltip(person ? 'Delete person' : 'Delete user'),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            person
                ? 'They have no linked login account'
                : 'This is your own administrator account',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Delete permanently'));
        await tester.pumpAndSettle();
        expect(writes, [
          person ? '/admin/people/1/delete' : '/admin/users/1/delete',
        ]);
        if (!person) {
          expect(
            find.text(
              'Your account has been permanently deleted. Close this window.',
            ),
            findsOneWidget,
          );
        }
      },
    );
  }
  for (final role in ['user', 'administrator']) {
    testWidgets('administration menu for $role', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(
            user: TestUser(),
            request: (path, {body}) async {
              if (path == '/me') {
                return {
                  'user': {'id': '1', 'account_role': role},
                  'households': [],
                };
              }
              return {'users': []};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('User menu'));
      await tester.pumpAndSettle();
      expect(
        find.text('Administration'),
        role == 'administrator' ? findsOneWidget : findsNothing,
      );
      if (role == 'administrator') {
        await tester.tap(find.text('Administration'));
        await tester.pumpAndSettle();
        expect(find.text('Users & table people'), findsOneWidget);
      }
    });
  }
  testWidgets(
    'deletion requires confirmation and cancellation sends no write',
    (tester) async {
      final writes = <String>[];
      var deleted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AdministrationPage(
            request: (path, {body}) async {
              if (path == '/me') {
                return {
                  'user': {'id': '1', 'account_role': 'administrator'},
                };
              }
              if (path == '/admin/users') {
                return {
                  'users': [
                    {
                      'id': '1',
                      'display_name': 'Admin',
                      'email': 'admin@example.test',
                      'account_role': 'administrator',
                    },
                    if (!deleted)
                      {
                        'id': '2',
                        'display_name': 'Guest',
                        'email': 'guest@example.test',
                        'account_role': 'user',
                      },
                  ],
                };
              }
              expect(body, {'confirm': true});
              writes.add(path);
              deleted = true;
              return {'deleted': true};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete user'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Delete user').last);
      await tester.pumpAndSettle();
      expect(find.text('Permanently delete user?'), findsOneWidget);
      expect(writes, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.byTooltip('Delete user').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(writes, ['/admin/users/2/delete']);
      expect(find.text('Guest'), findsNothing);
    },
  );

  testWidgets('ordinary account cannot list users', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AdministrationPage(
          request: (path, {body}) async {
            calls.add(path);
            return {
              'user': {'id': '2', 'account_role': 'user'},
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, ['/me']);
    expect(find.text('Administrator access is required.'), findsOneWidget);
  });

  testWidgets('failed deletion keeps the user visible and shows error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdministrationPage(
          request: (path, {body}) async {
            if (path == '/me') {
              return {
                'user': {'id': '1', 'account_role': 'administrator'},
              };
            }
            if (path == '/admin/users') {
              return {
                'users': [
                  {
                    'id': '2',
                    'display_name': 'Guest',
                    'email': 'guest@example.test',
                    'account_role': 'user',
                  },
                ],
              };
            }
            throw ApiException(503, 'Firebase unavailable');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Firebase unavailable'), findsOneWidget);
  });
}
