import 'package:coffey_table_recipes/src/recipe_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'durations display hours minutes and seconds without a raw second count',
    () {
      expect(formatRecipeTime(125), '2 min 5 sec');
      expect(formatRecipeTime(3665), '1 hr 1 min 5 sec');
      expect(formatRecipeTime(5), '0 min 5 sec');
      expect(formatRecipeTime(3665, clock: true), '1:01:05');
      expect(formatRecipeTime(125, clock: true), '2:05');
    },
  );
  test('time editors round trip native seconds and whole minute metadata', () {
    for (final seconds in [0, 5, 125, 3600, 86405]) {
      expect(parseRecipeTime(recipeTimeInput(seconds)), seconds);
    }
    for (final minutes in [0, 5, 125, 1440]) {
      expect(
        parseRecipeTime(
          recipeTimeInput(minutes, minutePrecision: true),
          minutePrecision: true,
        ),
        minutes,
      );
    }
    expect(parseRecipeTime('90:00'), 5400);
    for (final invalid in [
      '120',
      '-1:00',
      '1:60',
      '1:60:00',
      '1:00:60',
      '1.5:00',
      'abc',
      '',
    ]) {
      expect(parseRecipeTime(invalid), isNull);
    }
  });
}
