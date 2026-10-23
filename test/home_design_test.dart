import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestUser implements User {
  @override
  String get uid => 'test-user';
  @override
  String? get displayName => name;
  String name = 'Alex Example';
  @override
  Future<void> updateDisplayName(String? displayName) async {
    name = displayName!;
  }

  @override
  String? get email => 'alex@example.test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Recently deleted is reached beside Add recipe', (tester) async {
    final fetched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HouseholdPanel(
          user: TestUser(),
          request: (path, {body}) async {
            fetched.add(path);
            if (path == '/me') {
              return {
                'user': {'id': '42'},
                'households': [
                  {'id': '2', 'name': 'Coffey', 'role': 'member'},
                ],
              };
            }
            if (path.endsWith('/people')) return {'people': []};
            return {'recipes': [], 'next_offset': null};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recently deleted'), findsOneWidget);
    await tester.tap(find.text('Recently deleted'));
    await tester.pumpAndSettle();
    expect(fetched, contains('/households/2/recipes/deleted?offset=0'));
    expect(find.text('No recently deleted recipes.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Recently deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'table name edits own household person independently of account name',
    (tester) async {
      final user = TestUser();
      var tableName = 'Alex at dinner';
      var fail = false;
      final writes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(
            user: user,
            request: (path, {body}) async {
              if (path == '/me') {
                return {
                  'user': {'id': '42'},
                  'households': [
                    {'id': '2', 'name': 'Coffey', 'role': 'member'},
                  ],
                };
              }
              if (path.endsWith('/people/me/name')) {
                writes.add(path);
                if (fail) throw Exception('offline');
                tableName = body!['display_name'] as String;
                return {
                  'person': {
                    'id': '7',
                    'display_name': tableName,
                    'user_id': '42',
                  },
                };
              }
              if (path.endsWith('/people')) {
                return {
                  'people': [
                    {'id': '7', 'display_name': tableName, 'user_id': '42'},
                    {'id': '8', 'display_name': 'Sam', 'user_id': null},
                  ],
                };
              }
              return {'recipes': [], 'next_offset': null};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('User menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name at the table'));
      await tester.pumpAndSettle();
      expect(find.text('Alex at dinner'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(writes, isEmpty);
      await tester.enterText(find.byType(TextFormField), '  Lex  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tableName, 'Lex');
      expect(user.name, 'Alex Example');
      expect(writes, ['/households/2/people/me/name']);
      await tester.tap(find.byTooltip('User menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Household & people'));
      await tester.pumpAndSettle();
      expect(find.text('Lex'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      fail = true;
      await tester.tap(find.byTooltip('Change name at the table'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Unsaved');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Lex'), findsOneWidget);
      expect(
        find.text('Could not update your name at the table. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('user menu saves display name and confirms logout', (
    tester,
  ) async {
    final user = TestUser();
    var logoutCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HouseholdPanel(
          user: user,
          request: (path, {body}) async => {'households': []},
          signOut: () async {
            logoutCount++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('User menu'));
    await tester.pumpAndSettle();
    expect(find.text('alex@example.test'), findsOneWidget);
    await tester.tap(find.text('Account display name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  Jamie  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(user.name, 'Jamie');
    expect(find.text('J'), findsOneWidget);
    await tester.tap(find.byTooltip('User menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(logoutCount, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(logoutCount, 0);
    await tester.tap(find.byTooltip('User menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(logoutCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'household names save and people show account or invitation icons',
    (tester) async {
      final people = <Map<String, dynamic>>[
        {'display_name': 'Alex', 'user_id': 'test-user', 'child_mode': true},
        {'display_name': 'Sam', 'user_id': null},
      ];
      String householdName = 'Coffey';
      Future<Map<String, dynamic>> request(
        String path, {
        Map<String, dynamic>? body,
      }) async {
        if (path == '/me') {
          return {
            'households': [
              {'id': '2', 'name': householdName, 'role': 'owner'},
            ],
          };
        }
        if (path.endsWith('/name')) {
          householdName = body!['name'] as String;
          return {
            'household': {'id': '2', 'name': householdName, 'role': 'owner'},
          };
        }
        if (path.endsWith('/people')) {
          if (body != null) {
            people.add({'display_name': body['display_name'], 'user_id': null});
          }
          return {'people': List<Map<String, dynamic>>.from(people)};
        }
        return {'recipes': [], 'next_offset': null};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(user: TestUser(), request: request),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('User menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Household & people'));
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.byIcon(Icons.account_circle), findsOneWidget);
      expect(find.byTooltip('Child account'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Alex'),
          matching: find.byIcon(Icons.child_care),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Sam'),
          matching: find.byIcon(Icons.child_care),
        ),
        findsNothing,
      );
      expect(find.byTooltip('Has a login account'), findsNothing);
      await tester.tap(find.byTooltip('Invite to household'));
      await tester.pumpAndSettle();
      expect(find.text('Invite Sam'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit household name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Our table');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(householdName, 'Our table');
      expect(find.text('Our table'), findsOneWidget);
      await tester.tap(find.text('Add household member'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Jamie');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Jamie'), findsOneWidget);
      expect(find.byTooltip('Invite to household'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1000.0]) {
    testWidgets(
      'recipes are the home and Recipes menu clears search at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final paths = <String>[];
        Future<Map<String, dynamic>> request(
          String path, {
          Map<String, dynamic>? body,
        }) async {
          paths.add(path);
          if (path == '/me') {
            return {
              'households': [
                {'id': '2', 'name': 'Coffey', 'role': 'owner'},
                {'id': '3', 'name': 'Other household', 'role': 'member'},
              ],
            };
          }
          if (path.endsWith('/people')) {
            return {
              'people': [
                {'display_name': 'Alex', 'user_id': 'test-user'},
              ],
            };
          }
          return {
            'recipes': [
              {'id': '9', 'title': 'Family soup'},
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
        expect(find.text('Family soup'), findsOneWidget);
        expect(find.text('People at your table'), findsNothing);
        expect(find.text('Your household'), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byTooltip('User menu'), findsOneWidget);
        expect(find.text('Log out'), findsNothing);
        expect(paths.where((p) => p.endsWith('/people')), isNotEmpty);
        await tester.enterText(find.byType(TextField), 'soup');
        await tester.tap(find.byTooltip('User menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Household & people'));
        await tester.pumpAndSettle();
        expect(find.text('Coffey'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.text('Family soup'), findsNothing);
        expect(find.text('Alex'), findsOneWidget);
        expect(find.text('Add household member'), findsOneWidget);
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Recipes').last);
        await tester.pumpAndSettle();
        expect(find.text('Family soup'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        await tester.tap(find.byTooltip('User menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Household & people'));
        await tester.pumpAndSettle();
        expect(find.text('Other household'), findsNothing);
        expect(paths.any((path) => path.startsWith('/households/3/')), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
