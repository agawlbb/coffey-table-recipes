import 'dart:convert';
import 'dart:io';

import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:coffey_table_recipes/src/recipe_source_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class RecordingLauncher extends UrlLauncherPlatform {
  final calls = <({String url, LaunchOptions options})>[];
  @override
  get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url: url, options: options));
    return true;
  }
}

void main() {
  final cases = jsonDecode(
    File('test/fixtures/source_link_cases.json').readAsStringSync(),
  ) as List;
  for (final row in cases) {
    test('source website: ${row['value']}', () {
      expect(recipeSourceWebsite(row['value'])?.toString(), row['url']);
    });
  }

  test('whole source URLs retain meaningful trailing URL punctuation', () {
    const url = 'https://example.com/recipe!?x=1,';
    final parts = recipeSourceParts('  $url  ');
    expect(parts.map((part) => part.text).join(), '  $url  ');
    expect(parts.singleWhere((part) => part.uri != null).uri.toString(), url);
  });

  test('source prose and punctuation remain unchanged around multiple links', () {
    const text =
        "Book & author. See (https://example.com/recipe_(old)), or www.example.org.\nPage 42.";
    final parts = recipeSourceParts(text);
    expect(parts.map((part) => part.text).join(), text);
    expect(
      parts
          .where((part) => part.uri != null)
          .map((part) => part.uri.toString()),
      ['https://example.com/recipe_(old)', 'https://www.example.org'],
    );
    expect(
      recipeSourceParts('javascript:https://example.com').single.uri,
      isNull,
    );
    expect(
      recipeSourceParts('Family recipe.pdf, p. 42')
          .every((part) => part.uri == null),
      isTrue,
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('source links open an external browser on $platform', (
      tester,
    ) async {
      final original = UrlLauncherPlatform.instance;
      final launcher = RecordingLauncher();
      UrlLauncherPlatform.instance = launcher;
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() {
        UrlLauncherPlatform.instance = original;
        debugDefaultTargetPlatformOverride = null;
      });
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RecipeSourceText(
              'See https://example.com/recipe for details.',
            ),
          ),
        ),
      );
      final link = tester.widget<Link>(find.byType(Link));
      expect(link.target, LinkTarget.blank);
      expect(
        tester.getSemantics(find.byType(InkWell)).flagsCollection.isLink,
        isTrue,
      );
      await tester.tap(find.text('https://example.com/recipe'));
      await tester.pumpAndSettle();
      expect(launcher.calls.single.url, 'https://example.com/recipe');
      expect(
        launcher.calls.single.options.mode,
        PreferredLaunchMode.externalApplication,
      );
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('source links support keyboard activation and narrow layouts', (
    tester,
  ) async {
    final original = UrlLauncherPlatform.instance;
    final launcher = RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = original);
    final url = 'https://example.com/${'long-path-' * 25}';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 280, child: RecipeSourceText(url)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (!Focus.of(tester.element(find.text(url))).hasFocus) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(Focus.of(tester.element(find.text(url))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(launcher.calls.single.url, url);
  });

  testWidgets(
    'recipe details link source variants while preserving non-web text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecipeDetail(
            title: 'Test recipe',
            householdId: '2',
            recipeId: '9',
            request: (_) async => {
              'recipe': {
                'id': '9',
                'title': 'Test recipe',
                'source_type': 'ai_website',
                'source_title': 'Family cookbook',
                'source_author': 'A. Writer',
                'source_url': 'https://example.com/recipe',
                'source_reference': 'Also www.example.org. Printed page 42.',
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Family cookbook'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Website link'), findsOneWidget);
      expect(find.text('Family cookbook'), findsOneWidget);
      expect(find.text('A. Writer'), findsOneWidget);
      final urls = tester
          .widgetList<Link>(find.byType(Link))
          .map((link) => link.uri.toString());
      expect(
        urls,
        containsAll(['https://example.com/recipe', 'https://www.example.org']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsafe and malformed sources remain selectable plain text', (
    tester,
  ) async {
    const text = 'javascript:alert(1) <script>bad</script> recipe.pdf';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RecipeSourceText(text))),
    );
    expect(find.byType(Link), findsNothing);
    expect(find.widgetWithText(SelectableText, text), findsOneWidget);
  });
}
