import 'package:coffey_table_recipes/src/account_menu.dart';
import 'package:coffey_table_recipes/src/account_panel.dart';
import 'package:coffey_table_recipes/src/child_mode.dart';

import 'home_design_test.dart' show TestUser;

import 'package:coffey_table_recipes/src/native_timers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('account menu fits a narrow phone and routes every action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              AccountMenu(
                name: 'Alex with a long display name',
                email: 'long.email.address@example.test',
                onSelected: (value) => action = value,
              ),
            ],
          ),
        ),
      ),
    );
    for (final entry in {
      'Full name': 'name',
      'Child mode: Off': 'childMode',
      'Log out': 'logout',
    }.entries) {
      await tester.tap(find.byTooltip('User menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(action, entry.value);
    }
  });

  for (final restricted in [false, true]) {
    testWidgets('settings and administration respect child mode: $restricted', (
      tester,
    ) async {
      addTearDown(() => childMode.value = false);
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdPanel(
            user: TestUser(),
            request: (path, {body}) async {
              if (path == '/me') {
                return {
                  'user': {
                    'id': '42',
                    'account_role': 'administrator',
                    'child_mode': restricted,
                  },
                  'households': [
                    {'id': '2', 'name': 'Family', 'role': 'owner'},
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
      await tester.tap(find.byTooltip('User menu'));
      await tester.pumpAndSettle();
      expect(find.text('Household members'), findsNothing);
      expect(find.text('Administration'), findsNothing);
      expect(find.text('Timer settings'), findsNothing);
      final change = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('Full name'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(change.enabled, !restricted);
      expect(
        find.text('Child mode: ${restricted ? 'On' : 'Off'}'),
        findsOneWidget,
      );
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(
        find.text('Administration'),
        restricted ? findsNothing : findsOneWidget,
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final departments = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Shopping list departments'),
      );
      expect(departments.enabled, !restricted);
      expect(
        find.text('Cooking timers'),
        !restricted && NativeTimers.supported ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'tone selection only persists on Save and failed saves retain current tone',
    (tester) async {
      final writes = <String>[];
      var fail = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeTimers.channel, (call) async {
            if (call.method == 'settings') {
              return {
                'tone': '',
                'mode': 'Android system alarm information',
                'tones': [
                  {'value': '', 'label': 'Default alarm'},
                  ...List.generate(
                    20,
                    (i) => {'value': 'tone$i', 'label': 'Sound $i'},
                  ),
                ],
              };
            }
            if (call.method == 'setTone') {
              if (fail) throw PlatformException(code: 'save');
              writes.add((call.arguments as Map)['tone'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeTimers.channel, null),
      );
      await tester.pumpWidget(const MaterialApp(home: TimerSettings()));
      await tester.pumpAndSettle();
      expect(find.text('Receive timers from other devices'), findsOneWidget);
      final receive = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(receive.value, false);
      expect(receive.onChanged, isNull);
      await tester.tap(find.text('Alarm tone'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sound 19');
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is RadioListTile<String> && widget.value == 'tone19',
        ),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(find.text('Default alarm'), findsOneWidget);
      await tester.tap(find.text('Alarm tone'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sound 19');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is RadioListTile<String> && widget.value == 'tone19',
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes, ['tone19']);
      expect(find.text('Sound 19'), findsOneWidget);
      fail = true;
      await tester.tap(find.text('Alarm tone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Default alarm'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Sound 19'), findsOneWidget);
      expect(find.textContaining('Could not save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
