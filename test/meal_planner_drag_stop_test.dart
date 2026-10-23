import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffey_table_recipes/src/meal_planner.dart';

import 'meal_planner_test.dart' show PlanFixture;

void main() {
  for (final ending in [
    'release',
    'cancel',
    'background',
    'navigate',
    'hidden',
  ]) {
    testWidgets(
      'scrolling survives source leaving viewport and stops on $ending',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = PlanFixture();
        final navigator = GlobalKey<NavigatorState>();
        late StateSetter update;
        var active = true;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: StatefulBuilder(
              builder: (context, setter) {
                update = setter;
                return Scaffold(
                  body: MealPlanner(
                    householdId: '1',
                    householdName: 'Table',
                    request: fixture.request,
                    save: fixture.save,
                    active: active,
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byType(CustomScrollView);
        final controller = tester.widget<CustomScrollView>(list).controller!;
        final bounds = tester.getRect(list);
        final trash = tester.getRect(find.byKey(const ValueKey('meal-trash')));
        expect(trash.width, closeTo(bounds.width / 3, .01));
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Today soup')),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveTo(Offset(bounds.center.dx, bounds.bottom - 10));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 90));
        }
        expect(controller.offset, greaterThan(900));
        // Feedback remains, but the source tile has scrolled offscreen.
        expect(find.text('Today soup'), findsOneWidget);
        final beforeTrash = controller.offset;
        await gesture.moveTo(trash.center);
        await tester.pump(const Duration(milliseconds: 180));
        expect(controller.offset, beforeTrash);
        await gesture.moveTo(
          Offset(trash.right + trash.width / 2, trash.center.dy),
        );
        await tester.pump(const Duration(milliseconds: 180));
        expect(controller.offset, lessThan(beforeTrash));
        switch (ending) {
          case 'release':
            await gesture.up();
          case 'cancel':
            await gesture.cancel();
          case 'background':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
          case 'navigate':
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Elsewhere')),
              ),
            );
          case 'hidden':
            update(() => active = false);
        }
        await tester.pump(const Duration(milliseconds: 100));
        final stopped = controller.offset;
        if (ending == 'hidden' ||
            ending == 'background' ||
            ending == 'navigate') {
          await gesture.moveBy(const Offset(1, -1));
        }
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 90));
        }
        expect(controller.offset, stopped);
        expect(fixture.writes, isEmpty);
        if (ending != 'release' && ending != 'cancel') await gesture.cancel();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
