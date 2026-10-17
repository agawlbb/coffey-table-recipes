import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/recipe_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('favorite filter requires authenticated reads', () {
    expect(
      isPublicRecipeRead('/households/1/recipes?favorite_people=10'),
      isFalse,
    );
    expect(isPublicRecipeRead('/households/1/recipes'), isTrue);
  });
  testWidgets('heart toggles self and hold edits another household person', (
    tester,
  ) async {
    final favorites = <String, bool>{'10': false, '11': false};
    Map<String, dynamic> state() => {
      'current_person_id': '10',
      'people': [
        for (final id in favorites.keys)
          {
            'id': id,
            'display_name': id == '10' ? 'Joe' : 'Brooklyn',
            'favorite': favorites[id],
          },
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeDetail(
          householdId: '1',
          recipeId: '5',
          title: 'Soup',
          request: (path) async => path.endsWith('/favorites')
              ? state()
              : {
                  'recipe': {
                    'id': '5',
                    'title': 'Soup',
                    'steps': [],
                    'ingredients': [],
                  },
                },
          save: (path, body) async {
            favorites[body['person_id'] as String] = body['favorite'] as bool;
            return state();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Favorite (hold for household)'));
    await tester.pumpAndSettle();
    expect(favorites['10'], isTrue);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.longPress(find.byTooltip('Favorite (hold for household)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brooklyn'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(favorites['11'], isTrue);
    await tester.scrollUntilVisible(
      find.text('Favorite of Joe and Brooklyn'),
      250,
    );
    expect(find.text('Favorite of Joe and Brooklyn'), findsOneWidget);
  });
  testWidgets('favorite filter sends everyone selected and clears', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBrowser(
          householdId: '1',
          householdName: 'Table',
          request: (path) async {
            paths.add(path);
            return path.endsWith('/people')
                ? {
                    'people': [
                      {'id': '10', 'display_name': 'Joe'},
                      {'id': '11', 'display_name': 'Brooklyn'},
                    ],
                  }
                : {'recipes': []};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Joe'), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    final panel = tester.element(find.byType(AlertDialog));
    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(AlertDialog)), same(panel));
    await tester.tap(find.text('Joe'));
    await tester.tap(find.text('Brooklyn'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(Uri.parse(paths.last).queryParameters['favorite_people'], '10,11');
    await tester.tap(find.byTooltip('Filters (2 selected)'));
    await tester.pumpAndSettle();
    expect(find.text('Joe, Brooklyn'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.text('Clear'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      Uri.parse(paths.last).queryParameters.containsKey('favorite_people'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
