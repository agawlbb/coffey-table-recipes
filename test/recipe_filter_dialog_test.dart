import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coffey_table_recipes/src/recipe_filter_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recipe_ui_preview.dart';

final members = <Map<String, dynamic>>[
  {'id': '10', 'display_name': 'Joe'},
  {'id': '11', 'display_name': 'Val'},
  {'id': '12', 'display_name': 'Brooklyn'},
];

Future<void> openFilters(
  WidgetTester tester, {
  bool blank = false,
  Set<String> people = const {},
  Future<List<Map<String, dynamic>>> Function()? load,
  ValueChanged<RecipeFilterSelection?>? closed,
  GlobalKey? boundary,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: previewTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showDialog<RecipeFilterSelection>(
                  context: context,
                  builder: (_) => RecipeFilterDialog(
                    blankOnly: blank,
                    favoritePeople: people,
                    loadPeople: load ?? () async => members,
                  ),
                );
                closed?.call(result);
              },
              child: const Text('Open filters'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open filters'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pending member read does not block blank selection', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    RecipeFilterSelection? result;
    await openFilters(
      tester,
      load: () => pending.future,
      closed: (value) => result = value,
    );
    await tester.tap(find.text('Blank recipes only'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result?.blankOnly, isTrue);
    expect(result?.favoritePeople, isEmpty);
    pending.complete(members);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('member failure can retry without clearing the draft', (
    tester,
  ) async {
    var calls = 0;
    RecipeFilterSelection? result;
    await openFilters(
      tester,
      blank: true,
      people: {'10'},
      closed: (value) => result = value,
      load: () async {
        if (++calls == 1) throw StateError('Fixture failure');
        return members;
      },
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Joe'), findsOneWidget);
    await tester.tap(find.text('Val'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result?.blankOnly, isTrue);
    expect(result?.favoritePeople, {'10', '11'});
  });

  testWidgets('Clear is staged and Cancel preserves original selection', (
    tester,
  ) async {
    final original = {'10'};
    RecipeFilterSelection? result;
    var dismissed = false;
    await openFilters(
      tester,
      blank: true,
      people: original,
      closed: (value) {
        result = value;
        dismissed = true;
      },
    );
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Clear'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
    expect(result, isNull);
    expect(original, {'10'});
  });

  testWidgets('Escape dismisses changes without applying', (tester) async {
    RecipeFilterSelection? result;
    var dismissed = false;
    await openFilters(
      tester,
      closed: (value) {
        result = value;
        dismissed = true;
      },
    );
    await tester.tap(find.text('Blank recipes only'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
    expect(result, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final size in [const Size(960, 820), const Size(320, 700)]) {
    testWidgets('filter controls align and remain usable at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preview = Platform.environment['RECIPE_FILTER_PREVIEW_DIR'];
      if (preview != null) {
        await tester.runAsync(() async {
          final fontDir =
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
          final fonts = FontLoader('Roboto');
          for (final weight in ['regular', 'medium', 'bold']) {
            fonts.addFont(
              File('$fontDir/roboto-$weight.ttf')
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes)),
            );
          }
          await fonts.load();
          final icons = FontLoader('MaterialIcons');
          icons.addFont(
            File('$fontDir/materialicons-regular.otf')
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          );
          await icons.load();
        });
      }
      final boundary = GlobalKey();
      await openFilters(
        tester,
        boundary: boundary,
        blank: true,
        people: {'10', '11'},
      );
      final labels = ['Blank recipes only', 'Favorite'];
      expect(
        tester.getTopLeft(find.text(labels[0])).dx,
        tester.getTopLeft(find.text(labels[1])).dx,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Joe'),
            )
            .controlAffinity,
        ListTileControlAffinity.trailing,
      );
      expect(find.textContaining('everyone'), findsNothing);
      expect(tester.takeException(), isNull);
      if (preview != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(preview).create(recursive: true);
          await File('$preview/filters-${size.width.toInt()}.png')
              .writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets('many members and large text scroll while actions stay visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RecipeFilterSelection? result;
    await openFilters(
      tester,
      scale: 1.5,
      people: {'0'},
      closed: (value) => result = value,
      load: () async => List.generate(
        20,
        (i) => {'id': '$i', 'display_name': 'Household member $i'},
      ),
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Household member 19'));
    await tester.tap(find.text('Household member 19'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result?.favoritePeople, {'0', '19'});
    expect(tester.takeException(), isNull);
  });
}
