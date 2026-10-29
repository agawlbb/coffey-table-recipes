import 'package:coffey_table_recipes/src/android_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    int build = 39,
    String url = androidDownloadUrl,
    bool enabled = true,
    bool offline = false,
    Future<bool> Function()? download,
    VoidCallback? fetched,
  }) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) => AndroidUpdateHost(
          navigatorKey: navigator,
          enabled: enabled,
          installedBuild: () async => 38,
          registerPush: () async {},
          fetchRelease: () async {
            fetched?.call();
            if (offline) throw StateError('offline');
            return {'version': '2.3.0', 'build': build, 'url': url};
          },
          openDownload: download ?? () async => true,
          child: child!,
        ),
        home: const Scaffold(body: Text('Recipes')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'newer release shows link, launches download and permits dismissal',
    (tester) async {
      var downloads = 0;
      await open(
        tester,
        download: () async {
          downloads++;
          return true;
        },
      );
      expect(find.text('Android update available'), findsOneWidget);
      expect(find.text(androidDownloadUrl), findsOneWidget);
      await tester.tap(find.text('Download update'));
      await tester.pumpAndSettle();
      expect(downloads, 1);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Android update available'), findsNothing);
      expect(find.text('Recipes'), findsOneWidget);
    },
  );

  for (final build in [37, 38]) {
    testWidgets('installed build $build does not prompt', (tester) async {
      await open(tester, build: build);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  testWidgets('offline and untrusted download links leave app usable', (
    tester,
  ) async {
    await open(tester, offline: true);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester, url: 'https://example.com/untrusted.apk');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Recipes'), findsOneWidget);
  });

  testWidgets('other platforms skip checks', (tester) async {
    var checks = 0;
    await open(tester, enabled: false, fetched: () => checks++);
    expect(checks, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('failed browser launch keeps selectable link and retry', (
    tester,
  ) async {
    await open(tester, download: () async => false);
    await tester.tap(find.text('Download update'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open the download'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('resume checks again without stacking dialogs', (tester) async {
    var checks = 0;
    await open(tester, fetched: () => checks++);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(checks, 1);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
