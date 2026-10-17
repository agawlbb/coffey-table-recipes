import 'dart:io';
import 'dart:ui' as ui;

import 'package:coffey_table_recipes/src/blank_recipe_detail.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recipe_ui_preview.dart';

void main() {
  for (final size in [
    const Size(373, 700),
    const Size(960, 820),
    const Size(320, 700),
  ]) {
    testWidgets(
      'blank display has one title and aligned controls at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preview = Platform.environment['BLANK_RECIPE_PREVIEW_DIR'];
        if (preview != null) {
          final fontDir =
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
          await tester.runAsync(() async {
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
        final title = size.width == 320
            ? 'Grandma’s chicken with mushrooms and cream'
            : 'Chicken Alfrado';
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: previewTheme(),
              home: RecipeDetail(
                householdId: '2',
                recipeId: '9',
                title: title,
                request: (path) async => path.endsWith('/favorites')
                    ? {'people': []}
                    : {
                        'recipe': {
                          'id': '9',
                          'title': title,
                          'source_type': 'blank',
                          'photos': [],
                        },
                      },
                save: (_, body) async => {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text('Blank recipe'), findsOneWidget);
        expect(find.byTooltip('Delete recipe'), findsOneWidget);
        expect(find.byTooltip('Favorite (hold for household)'), findsOneWidget);
        final picture = tester.getRect(
          find.byKey(const ValueKey('blank-recipe-picture')),
        );
        final imports = tester.getRect(
          find.byKey(const ValueKey('blank-recipe-import')),
        );
        expect(picture.left, imports.left);
        expect(picture.width, imports.width);
        final textButton = find.widgetWithText(OutlinedButton, 'Text');
        final website = find.widgetWithText(OutlinedButton, 'Website');
        expect(tester.getSize(textButton), tester.getSize(website));
        expect(tester.getSize(textButton).height, greaterThanOrEqualTo(48));
        expect(find.byType(ChoiceChip), findsNothing);
        expect(tester.takeException(), isNull);
        if (preview != null) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(preview).create(recursive: true);
            await File('$preview/blank-recipe-${size.width.toInt()}.png')
                .writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }

  testWidgets(
    'blank presentation retains favorite, picture and import interactions',
    (tester) async {
      var favorites = 0;
      var household = 0;
      var pictures = 0;
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlankRecipeDetail(
              title: 'Cake',
              photos: const [],
              favorite: true,
              favoriteNames: 'Alice',
              onFavorite: () => favorites++,
              onHouseholdFavorites: () => household++,
              onPicture: () => pictures++,
              onImport: (kind) => selected = kind,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heart = find.byTooltip('Favorite (hold for household)');
      await tester.tap(heart);
      await tester.longPress(heart);
      await tester.tap(find.text('Add picture'));
      await tester.tap(find.text('Website'));
      expect(favorites, 1);
      expect(household, 1);
      expect(pictures, 1);
      expect(selected, 'website');
      expect(find.text('Favorite of Alice'), findsOneWidget);
    },
  );

  testWidgets('large text uses full-width import buttons on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: BlankRecipeDetail(
            title: 'Cake',
            photos: const [],
            favorite: false,
            onImport: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.getRect(find.widgetWithText(OutlinedButton, 'Text'));
    final website = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Website'),
    );
    expect(text.left, website.left);
    expect(website.top, greaterThanOrEqualTo(text.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline blank shows disabled import controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlankRecipeDetail(
            title: 'Cake',
            photos: const [],
            favorite: false,
            offline: true,
            onImport: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Website'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Connect to the internet to import.'), findsOneWidget);
  });
}
