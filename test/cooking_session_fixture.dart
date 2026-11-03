import 'package:coffey_table_recipes/src/cooking_sessions.dart';

CookingSessions recipeCookingFixture() {
  Map<String, dynamic>? state;
  return CookingSessions(
    installation: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    request: (path, {body}) async {
      state ??= {
        'id': body?['session_id'] ?? '11111111111111111111111111111111',
        'revision': 1,
        'ended_at': null,
        'created_at': 1800000000000,
        'household_id': '2',
        'recipe': {
          'id': body?['recipe_id'] ?? '1',
          'title': 'Soup',
          'steps': [
            {'id': 's', 'position': 1, 'instruction': 'Stir.'},
          ],
          'actions': <Map<String, dynamic>>[],
        },
        'completed': <String>[],
        'step_revisions': <String, dynamic>{},
        'timers': <Map<String, dynamic>>[],
        'joined_devices': ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
      };
      return {'session': state};
    },
  );
}
