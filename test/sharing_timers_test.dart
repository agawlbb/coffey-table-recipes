import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/native_timers.dart';
import 'package:coffey_table_recipes/src/shared_recipe_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only public recipe GET paths bypass the identity token', () {
    expect(isPublicRecipeRead('/households/2/recipes?q=soup'), isTrue);
    expect(isPublicRecipeRead('/households/2/recipes/9'), isTrue);
    for (final path in [
      '/me',
      '/households/2/recipes/deleted',
      '/households/2/recipes/9/restore',
      '/households/2/recipes/9/attach',
      '/households/2/people',
    ]) {
      expect(isPublicRecipeRead(path), isFalse);
    }
  });
  test('shared HTTPS links validate host, path and numeric id', () {
    expect(
      recipeIdFromLink(
        'https://coffeybean.com/CoffeyTableRecipes/share.php?id=12',
      ),
      '12',
    );
    expect(recipeIdFromLink('/CoffeyTableRecipes/share.php?id=12'), '12');
    expect(
      recipeIdFromLink(
        'http://coffeybean.com/CoffeyTableRecipes/share.php?id=12',
      ),
      isNull,
    );
    expect(
      recipeIdFromLink(
        'https://example.com/CoffeyTableRecipes/share.php?id=12',
      ),
      isNull,
    );
    expect(recipeIdFromLink('/CoffeyTableRecipes/share.php?id=0'), isNull);
    expect(recipeIdFromLink('/CoffeyTableRecipes/share.php?id=12x'), isNull);
  });
  test(
    'native timer IDs isolate recipes and permission failures propagate',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeTimers.channel, (call) async {
            calls.add(call);
            if (call.method == 'schedule' &&
                (call.arguments as Map)['key'] == 'denied') {
              throw PlatformException(code: 'permission');
            }
            if (call.method == 'list') {
              return [
                {'key': '1:2', 'deadline': 1000},
                {'key': '2:2', 'deadline': 2000},
              ];
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeTimers.channel, null),
      );
      final time = DateTime.fromMillisecondsSinceEpoch(123456);
      await NativeTimers.schedule('1:2', time, 'Soup');
      await NativeTimers.schedule('2:2', time, 'Bread');
      await NativeTimers.cancel('1:2');
      expect((await NativeTimers.restore()).length, 2);
      expect((calls[0].arguments as Map)['deadline'], 123456);
      expect((calls[1].arguments as Map)['key'], '2:2');
      expect((calls[2].arguments as Map)['key'], '1:2');
      await expectLater(
        NativeTimers.schedule('denied', time, 'Soup'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
