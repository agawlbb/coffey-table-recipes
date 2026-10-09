import 'package:coffey_table_recipes/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('web scrollbars remain visible and dragging moves the list', (
    tester,
  ) async {
    final vertical = ScrollController();
    final horizontal = ScrollController();
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(
          webScrollbars: true,
          touchCapable: false,
        ),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 300,
                child: ListView(
                  controller: vertical,
                  children: List.generate(
                    30,
                    (i) => SizedBox(height: 60, child: Text('Recipe $i')),
                  ),
                ),
              ),
              SizedBox(
                height: 100,
                child: ListView(
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  children: List.generate(
                    10,
                    (i) => SizedBox(width: 200, child: Text('Photo $i')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    final bars = tester.widgetList<Scrollbar>(find.byType(Scrollbar)).toList();
    expect(bars, hasLength(2));
    expect(
      bars.every(
        (bar) =>
            bar.thumbVisibility! &&
            !bar.trackVisibility! &&
            bar.interactive! &&
            bar.thickness == 7,
      ),
      isTrue,
    );
    expect(
      bars.map((bar) => bar.controller),
      containsAll([vertical, horizontal]),
    );
    final rect = tester.getRect(find.byType(Scrollbar).first);
    await tester.dragFrom(
      Offset(rect.right - 3, rect.top + 15),
      const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    expect(vertical.offset, greaterThan(0));
    expect(horizontal.offset, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'touch-capable web devices hide bars and retain swipe scrolling',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(
            webScrollbars: true,
            touchCapable: true,
          ),
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: List.generate(
                30,
                (i) => SizedBox(height: 60, child: Text('Recipe $i')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
}
