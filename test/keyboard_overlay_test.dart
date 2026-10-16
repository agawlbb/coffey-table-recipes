import 'package:coffey_table_recipes/src/app.dart';
import 'package:coffey_table_recipes/src/offline_recipes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app keyboard dismiss control has an overlay', (tester) async {
    await tester.pumpWidget(const CoffeyTableApp());
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Dismiss keyboard'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss keyboard'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('offline app badge has a tooltip overlay', (tester) async {
    addTearDown(() => offlineStatus.value = false);
    offlineStatus.value = true;
    await tester.pumpWidget(const CoffeyTableApp());
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
    offlineStatus.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
