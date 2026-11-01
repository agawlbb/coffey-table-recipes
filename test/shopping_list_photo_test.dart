import 'dart:async';
import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/child_mode.dart';
import 'package:coffey_table_recipes/src/shopping_list.dart';
import 'package:coffey_table_recipes/src/shopping_photo.dart';
import 'package:coffey_table_recipes/src/shopping_changes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final photo = 'a' * 64;
  final replacement = 'b' * 64;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
  );
  late List<Map<String, dynamic>> items;
  late int writes;
  late int uploads;
  late String uploadedPhoto;
  late bool failUpload;
  late bool failRead;

  setUp(() {
    childMode.value = false;
    items = [
      {
        'id': 'milk',
        'name': 'Milk',
        'note': 'Blue carton',
        'department': 'Dairy',
        'checked': false,
      },
    ];
    writes = 0;
    uploads = 0;
    uploadedPhoto = photo;
    failUpload = false;
    failRead = false;
  });
  tearDown(() => childMode.value = false);

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (path.endsWith('/photos')) {
      uploads++;
      if (failUpload) throw ApiException(503, 'Unavailable');
      expect(base64Decode(body!['image_base64'] as String), png);
      return {'photo': uploadedPhoto};
    }
    if (path.contains('/photos/')) {
      if (failRead) throw ApiException(503, 'Unavailable');
      return {'image_base64': base64Encode(png)};
    }
    if (body != null) {
      writes++;
      items = List<Map<String, dynamic>>.from(body['items'] as List);
    }
    return {
      'revision': writes,
      'departments': ['Dairy'],
      'items': items,
    };
  }

  Future<void> open(
    WidgetTester tester,
    Future<Uint8List?> Function(ShoppingPhotoSource) pick,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingListScreen(
          householdId: '1',
          householdName: 'Our table',
          request: request,
          pickPhoto: pick,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester) async {
    await tester.tap(find.text('Milk'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all attachment sources, replacement and removal use the inline save',
    (tester) async {
      ShoppingPhotoSource? selected;
      await open(tester, (source) async {
        selected = source;
        return png;
      });
      for (final entry in {
        'Camera': ShoppingPhotoSource.camera,
        'Choose file': ShoppingPhotoSource.file,
        'Paste image': ShoppingPhotoSource.clipboard,
      }.entries) {
        await edit(tester);
        await tester.enterText(
          find.byKey(const ValueKey('note-milk')),
          'Blue carton',
        );
        await tester.tap(
          find.text(uploads == 0 ? 'Attach photo' : 'Replace photo'),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('note-milk')), findsOneWidget);
        uploadedPhoto = uploads == 0 ? photo : replacement;
        final before = writes;
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(selected, entry.value);
        expect(writes, before);
        expect(find.text('Remove photo'), findsOneWidget);
        await tester.tap(find.byTooltip('Save item'));
        await tester.pumpAndSettle();
        expect(items.single['photo'], uploadedPhoto);
        expect(items.single['note'], 'Blue carton');
        expect(items.single['checked'], false);
        expect(items.single['department'], 'Dairy');
        expect(find.text('View photo'), findsOneWidget);
      }
      await edit(tester);
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save item'));
      await tester.pumpAndSettle();
      expect(items.single['photo'], '');
      expect(find.text('View photo'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'picker cancellation and failed replacement preserve photo and pending text',
    (tester) async {
      items = [
        {...items.single, 'photo': photo},
      ];
      final pending = Completer<Uint8List?>();
      await open(tester, (_) => pending.future);
      await edit(tester);
      await tester.enterText(
        find.byKey(const ValueKey('note-milk')),
        'New note',
      );
      await tester.tap(find.text('Replace photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Save item',
              ),
            )
            .onPressed,
        isNull,
      );
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(uploads, 0);
      expect(find.text('New note'), findsOneWidget);
      await tester.tap(find.byTooltip('Save item'));
      await tester.pumpAndSettle();
      expect(items.single['photo'], photo);
      expect(items.single['note'], 'New note');
      await tester.pumpWidget(const SizedBox());

      failUpload = true;
      await open(tester, (_) async => png);
      await edit(tester);
      await tester.enterText(
        find.byKey(const ValueKey('note-milk')),
        'Keep this edit',
      );
      final before = writes;
      await tester.tap(find.text('Replace photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();
      expect(writes, before);
      expect(find.text('Keep this edit'), findsOneWidget);
      expect(find.textContaining('Could not attach'), findsOneWidget);
      await tester.tap(find.byTooltip('Save item'));
      await tester.pumpAndSettle();
      expect(items.single['photo'], photo);
      expect(items.single['note'], 'Keep this edit');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'view photo opens a zoomable viewer without checking off, including child mode',
    (tester) async {
      items = [
        {...items.single, 'photo': photo},
      ];
      childMode.value = true;
      failRead = true;
      await open(tester, (_) async => png);
      await tester.tap(find.text('View photo'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load photo. Tap to retry.'), findsOneWidget);
      failRead = false;
      await tester.tap(find.text('Could not load photo. Tap to retry.'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(writes, 0);
      expect(items.single['checked'], false);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native image paste reads only on request and rejects missing or oversized content',
    (tester) async {
      const channel = MethodChannel('pasteboard');
      var reads = 0;
      Uint8List? clipboard = png;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'image');
            reads++;
            return clipboard;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(reads, 0);
      expect(
        await pickShoppingPhoto(context, ShoppingPhotoSource.clipboard),
        png,
      );
      clipboard = null;
      await expectLater(
        pickShoppingPhoto(context, ShoppingPhotoSource.clipboard),
        throwsFormatException,
      );
      clipboard = Uint8List(5 * 1024 * 1024 + 1);
      await expectLater(
        pickShoppingPhoto(context, ShoppingPhotoSource.clipboard),
        throwsFormatException,
      );
      expect(reads, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('queued photo replacement preserves a remote checkoff', () {
    final base = items.single;
    final remote = {...base, 'checked': true, 'photo': photo};
    final result = overlayShoppingChanges(
      {
        'revision': 2,
        'items': [remote],
      },
      [
        {
          'body': {
            'base_items': [base],
            'items': [
              {...base, 'photo': replacement},
            ],
          },
        },
      ],
    );
    expect(result['items'][0]['photo'], replacement);
    expect(result['items'][0]['checked'], true);
  });
}
