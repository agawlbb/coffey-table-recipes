import 'package:coffey_table_recipes/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 1000.0]) {
    testWidgets('welcome artwork and text fit at $width pixels', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(2)),
                child: const TableWelcomeBanner(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("What's for dinner?"), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
