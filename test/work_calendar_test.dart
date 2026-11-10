import 'package:coffey_table_recipes/src/local_data.dart';
import 'package:coffey_table_recipes/src/meal_planner.dart';
import 'package:coffey_table_recipes/src/work_calendar_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'snapshot_database_test.dart' show snapshot;

void main() {
  testWidgets('only a color bar marks dates, and incoming changes move it', (
    tester,
  ) async {
    var calendar = <String, dynamic>{
      'dates': ['2026-11-10'],
      'color': '#1976D2',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealPlanner(
            householdId: '1',
            householdName: 'Table',
            now: () => DateTime(2026, 11, 10),
            request: (path) async => path.endsWith('/work-calendar')
                ? calendar
                : {'entries': [], 'today': '2026-11-10'},
            save: (_, _) async => {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byKey(const ValueKey('workday-bar-2026-11-10'));
    expect(bar, findsOneWidget);
    expect(tester.widget<Container>(bar).color, const Color(0xff1976d2));
    expect(find.text('Working'), findsNothing);
    expect(find.byTooltip('Working'), findsNothing);
    calendar = {
      'dates': ['2026-11-11'],
      'color': '#388E3C',
    };
    localDataChanges.value = '/households/1/work-calendar#update';
    await tester.pumpAndSettle();
    expect(bar, findsNothing);
    expect(
      find.byKey(const ValueKey('workday-bar-2026-11-11')),
      findsOneWidget,
    );
    calendar = {'dates': [], 'color': '#388E3C'};
    localDataChanges.value = '/households/1/work-calendar#delete';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workday-bar-2026-11-11')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings saves selected household color', (tester) async {
    final writes = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkCalendarSetting(
            householdId: '1',
            request: (_) async => {'color': '#E09F3E'},
            save: (path, body) async {
              expect(path, '/households/1/work-calendar');
              writes.add(body);
              return body;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workday color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Blue'));
    await tester.pumpAndSettle();
    expect(writes, [
      {'color': '#1976D2'},
    ]);
    expect(
      tester.widget<Icon>(find.byType(Icon).last).color,
      const Color(0xff1976d2),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('dates and color survive restart offline, then deliver and accept incoming changes', () async {
    const path = '/households/1/work-calendar';
    final disk = <String, String>{};
    final delivered = <Map<String, dynamic>>[];
    var online = false;
    LocalData store(String key) => LocalData(
      key: key,
      fetch: (_) async => throw StateError('offline'),
      send: (path, body) async {
        delivered.add(body);
        return {
          'dates': ['2026-11-10'],
          ...body,
        };
      },
      readStore: (key) async => disk[key],
      writeStore: (key, value) async => disk[key] = value,
    )..connected = () => online;
    final source = snapshot('Soup');
    (source['responses'] as Map)[path] = {
      'dates': ['2026-11-10'],
      'color': '#E09F3E',
    };
    final first = store('work-calendar-test');
    await first.installSnapshot(source);
    expect(first.ownsWrite(path), isTrue);
    await first.save(path, {'color': '#1976D2'});
    expect((await first.request(path))['dates'], ['2026-11-10']);
    first.dispose();
    final restored = store('work-calendar-test');
    expect((await restored.request(path))['color'], '#1976D2');
    online = true;
    await restored.synchronize();
    expect(delivered, [
      {'color': '#1976D2'},
    ]);
    (source['responses'] as Map)[path] = {
      'dates': ['2026-11-12'],
      'color': '#388E3C',
    };
    await restored.installSnapshot(source);
    expect((await restored.request(path))['dates'], ['2026-11-12']);
    expect((await restored.request(path))['color'], '#388E3C');
    final other = store('other-account');
    await expectLater(other.request(path), throwsStateError);
    restored.dispose();
    other.dispose();
  });
}
