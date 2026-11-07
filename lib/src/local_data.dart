import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'client_log.dart';
import 'local_sqlite.dart';

import 'dart:math';

String? localRecipeCover(Map recipe) {
  final photos = [
    for (final row in (recipe['photos'] as List? ?? []))
      Map<String, dynamic>.from(row as Map),
  ];
  photos.sort(
    (a, b) =>
        ((b['is_cover'] == true || '${b['is_cover']}' == '1') ? 1 : 0) -
        ((a['is_cover'] == true || '${a['is_cover']}' == '1') ? 1 : 0),
  );
  for (final photo in photos) {
    if (photo['image_base64'] is String) {
      return 'data:image/png;base64,${photo['image_base64']}';
    }
    final url = photo['source_url'];
    if (url is String && url.isNotEmpty) return url;
  }
  return recipe['photo_url'] as String?;
}

typedef LocalRead = Future<Map<String, dynamic>> Function(String path);
typedef LocalWrite = Future<Map<String, dynamic>> Function(
  String path,
  Map<String, dynamic> body,
);

/// A notification carries a resource path, never account data. Screens re-read
/// their account's repository; the network never owns their loading state.
final localDataChanges = ValueNotifier<String>('');

/// Local working data. Screens never wait for network writes.
class LocalData extends ChangeNotifier {
  LocalData({
    required this.key,
    required this.fetch,
    required this.send,
    this.readStore = readLocalSqlite,
    this.writeStore = writeLocalSqlite,
  });
  final String key;
  final LocalRead fetch;
  final LocalWrite send;
  final Future<String?> Function(String) readStore;
  final Future<void> Function(String, String) writeStore;
  Map<String, dynamic> _server = {}, _data = {};
  final List<Map<String, dynamic>> _pending = [];
  final Set<String> _sending = {};
  bool Function() connected = () => false;
  DateTime Function() now = DateTime.now;
  List<Map<String, dynamic>> get decisions =>
      _pending.where((e) => e['review'] == true).map(_copy).toList();
  bool get hasAutomatic => _pending.any((e) => e['review'] != true);
  static String newId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void>? _loaded;
  Future<void> _edits = Future.value();
  bool _closed = false;
  int _generation = 0;
  final _revoked = <String>{};
  static int _epoch = 0;
  static Map<String, dynamic> _copy(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  bool _under(String path, String prefix) =>
      path == prefix ||
      path.startsWith(prefix.endsWith('/') ? prefix : '$prefix/');
  String _path(String path) {
    final aliases = _data['local-aliases'] as Map? ?? {};
    for (final alias in (_data['photo-aliases'] as Map? ?? {}).entries) {
      path = path.replaceAll('/photos/${alias.key}', '/photos/${alias.value}');
    }
    for (final alias in aliases.entries) {
      path = path.replaceAll(
        '/recipes/${alias.key}',
        '/recipes/${alias.value}',
      );
    }
    final uri = Uri.parse(path);
    final keys = uri.queryParameters.keys.toList()..sort();
    return Uri(
      path: uri.path,
      queryParameters: keys.isEmpty
          ? null
          : {for (final key in keys) key: uri.queryParameters[key]!},
    ).toString();
  }

  Future<void> _load() => _loaded ??= () async {
    try {
      final text = await readStore('local-first-v1-$key');
      if (text != null && text.isNotEmpty) {
        final saved = jsonDecode(text) as Map;
        _server = Map<String, dynamic>.from(saved['data'] as Map);
        _pending.addAll(
          (saved['pending'] as List? ?? []).map((e) => _copy(e as Map)),
        );
        _rebuild();
      }
    } catch (error) {
      clientLog.record('storage', 'cache_read_failed', error: error);
      if (error is FormatException || error is TypeError) {
        _server = {};
        _rebuild();
        return;
      }
      _loaded = null;
      rethrow;
    }
  }();
  Future<void> _commit(Map<String, dynamic> data, String path) async {
    await writeStore(
      'local-first-v1-$key',
      jsonEncode({'data': data, 'pending': _pending}),
    );
    _server = data;
    _rebuild();
    _generation++;
    if (!_closed) {
      notifyListeners();
      localDataChanges.value = '$path#${++_epoch}';
    }
  }

  bool _accessible(String path) {
    final parts = Uri.parse(path).pathSegments;
    if (parts.length < 2 || parts.first != 'households') return true;
    final account = _server['/me'] as Map?;
    if (account == null) return true;
    return (account['households'] as List).any((h) => '${h['id']}' == parts[1]);
  }

  void _rebuild() {
    _data = _copy(_server);
    for (final entry in _pending) {
      if (!_accessible(entry['path'] as String)) continue;
      if (entry['expires'] is int &&
          (entry['expires'] as int) <= now().millisecondsSinceEpoch) {
        continue;
      }
      _apply(_data, entry);
    }
  }

  Future<void> _serial(Future<void> Function() action) {
    final task = _edits.catchError((Object _) {}).then((_) => action());
    _edits = task;
    return task;
  }

  Future<Map<String, dynamic>?> cachedView(String path) => cached(path);
  Future<Map<String, dynamic>> blank(String path) async =>
      await cached(path) ??
      {
        'recipe': {
          'title': '',
          'source_type': 'blank',
          'measurement_system': 'unspecified',
          'original_language': 'en',
          'groups': [],
          'ingredients': [],
          'steps': [],
          'actions': [],
          'photos': [],
          'tags': [],
          'category_assignments': [],
          'pairings': [],
          'edit_options':
              _data['snapshot-options:${Uri.parse(path).pathSegments[1]}'] ??
              {},
        },
      };
  Future<void> acceptAccountSnapshot(Map<String, dynamic> account) => _serial(
    () async {
      await _load();
      if (account['households'] is! List) {
        throw const FormatException('Invalid household membership response');
      }
      final members = (account['households'] as List)
          .map((h) => '${h['id']}')
          .toSet();
      final next = Map<String, dynamic>.from(_server);
      next.removeWhere(
        (path, _) =>
            path.startsWith('/households/') &&
            !members.contains(Uri.parse(path).pathSegments[1]),
      );
      for (final kind in ['version', 'options', 'categories']) {
        next.removeWhere(
          (path, _) =>
              path.startsWith('snapshot-$kind:') &&
              !members.contains(path.split(':').last),
        );
      }
      _revoked.removeWhere(
        (prefix) =>
            prefix == '/' || members.any((id) => prefix == '/households/$id/'),
      );
      next['/me'] = _copy(account);
      await _commit(next, '/me');
    },
  );
  Future<void> installSnapshot(
    Map<String, dynamic> snapshot,
  ) => _serial(() async {
    await _load();
    if (snapshot['schema'] != 1 ||
        snapshot['household_id'] is! String ||
        snapshot['recipes'] is! List ||
        snapshot['responses'] is! Map ||
        snapshot['categories'] is! List ||
        snapshot['edit_options'] is! Map) {
      throw const FormatException('Incomplete household snapshot');
    }
    final household = snapshot['household_id'] as String;
    final prefix = '/households/$household/';
    final responses = snapshot['responses'] as Map;
    if (responses.entries.any(
      (e) =>
          e.key is! String ||
          !(e.key as String).startsWith(prefix) ||
          e.value is! Map,
    )) {
      throw const FormatException('Invalid household snapshot scope');
    }
    if ((snapshot['recipes'] as List).any(
      (row) =>
          row is! Map ||
          responses['${prefix}recipes/${row['id']}'] is! Map ||
          (responses['${prefix}recipes/${row['id']}'] as Map)['recipe'] is! Map,
    )) {
      throw const FormatException('Incomplete recipe snapshot');
    }
    final next = Map<String, dynamic>.from(_server);
    final shopping = next['${prefix}shopping-list'];
    final deleted =
        (responses['${prefix}recipes/deleted'] as Map?)?['recipes'] as List? ??
        [];
    for (final row in deleted) {
      final detail = '${prefix}recipes/${row['id']}';
      if (next[detail] is Map) next['deleted:$detail'] = next[detail];
    }

    next.removeWhere(
      (path, _) =>
          path.startsWith(prefix) && !path.contains('/shopping-list/photos/'),
    );
    for (final entry in responses.entries) {
      next[entry.key as String] = _copy(entry.value as Map);
    }
    if (shopping != null) {
      next['${prefix}shopping-list'] = shopping;
    }
    next['snapshot-version:$household'] = true;
    next['snapshot-categories:$household'] = snapshot['categories'];
    next['snapshot-options:$household'] = snapshot['edit_options'];
    if (next['/me'] is Map &&
        snapshot['household'] is Map &&
        snapshot['user'] is Map) {
      final account = _copy(next['/me'] as Map);
      account['user'] = {
        ...?account['user'] as Map?,
        ...snapshot['user'] as Map,
      };
      account['households'] = [
        for (final row in account['households'] as List)
          if (row['id'] == household)
            {...row as Map, ...snapshot['household'] as Map}
          else
            row,
      ];
      next['/me'] = account;
    }
    await _commit(next, '${prefix}recipes');
    if (!_closed) {
      for (final resource in [
        'shopping-list',
        'restaurants',
        'meal-plan',
        'people',
      ]) {
        localDataChanges.value = '$prefix$resource#${++_epoch}';
      }
    }
  });
  Future<void> acceptShopping(String household, Map<String, dynamic> state) =>
      _serial(() async {
        await _load();
        if (state['items'] is! List) {
          throw const FormatException('Invalid shopping snapshot');
        }
        final path = '/households/$household/shopping-list';
        await _commit({..._server, path: _copy(state)}, path);
      });
  Map<String, dynamic> readView(String input) {
    final path = _path(input), uri = Uri.parse(input);
    if (_revoked.any((prefix) => _under(path, prefix))) {
      throw ApiException(403, 'Access to this data was removed.');
    }
    final browse = _snapshotBrowse(uri);
    if (browse != null) return browse;
    if (_data[path] is Map) {
      return uri.path.endsWith('/meal-plan')
          ? _filterPlan(_data[path] as Map, uri)
          : _copy(_data[path] as Map);
    }
    if (uri.pathSegments.length == 4 &&
        uri.pathSegments[2] == 'recipes' &&
        _data.containsKey('snapshot-version:${uri.pathSegments[1]}')) {
      throw ApiException(
        404,
        'This recipe is no longer available.',
        code: 'recipe_not_found',
      );
    }
    throw StateError('Local cache is incomplete for $path');
  }

  Future<Map<String, dynamic>> request(String path) async =>
      await cached(path) ?? await refresh(path);
  Future<Map<String, dynamic>> refresh(
    String input, {
    bool force = false,
  }) async {
    await _load();
    final path = _path(input), generation = _generation;
    late Map<String, dynamic> result;
    try {
      result = await fetch(path);
    } on ApiException catch (error) {
      final parts = Uri.parse(path).pathSegments;
      String? prefix;
      if (['account_disabled', 'account_deleted'].contains(error.code)) {
        prefix = '/';
      }
      if (error.code == 'household_not_found' && parts.length > 1) {
        prefix = '/households/${parts[1]}/';
      }
      if (error.code == 'recipe_not_found') prefix = Uri.parse(path).path;
      if (prefix != null) {
        final removed = prefix;
        _revoked.add(removed);
        await _serial(
          () => _commit(
            Map<String, dynamic>.from(_server)..removeWhere(
              (p, _) =>
                  removed == '/' ||
                  _under(p, removed) ||
                  (removed.endsWith('/') &&
                      parts.length > 1 &&
                      p.startsWith('snapshot-') &&
                      p.endsWith(':${parts[1]}')),
            ),
            path,
          ),
        );
      }
      rethrow;
    }
    if (_revoked.any((prefix) => _under(path, prefix))) {
      throw ApiException(403, 'Access to this data was removed.');
    }
    if (_generation != generation) return await cached(path) ?? result;
    if (path == '/me') {
      await acceptAccountSnapshot(result);
    } else {
      await _serial(
        () => _commit({
          ..._server,
          path: _copy(result),
          if (Uri.parse(path).path.endsWith('/meal-plan'))
            Uri.parse(path).path: _copy(result),
        }, path),
      );
    }
    return result;
  }

  Future<Map<String, dynamic>?> cached(String input) async {
    await _load();
    final path = _path(input), uri = Uri.parse(_path(input));
    if (_revoked.any((prefix) => _under(path, prefix))) return null;
    if (uri.path.endsWith('/meal-plan/history') && _data[uri.path] is Map) {
      final result = _copy(_data[uri.path] as Map);
      final from = uri.queryParameters['from'], to = uri.queryParameters['to'];
      for (final field in ['planned_history', 'recorded_history']) {
        result[field] = (result[field] as List? ?? []).where((entry) {
          final day = '${entry['cooked_date'] ?? entry['cooked_at']}'.substring(
            0,
            10,
          );
          return (from == null || day.compareTo(from) >= 0) &&
              (to == null || day.compareTo(to) <= 0);
        }).toList();
      }
      return result;
    }
    final browse = _snapshotBrowse(uri);
    if (browse != null) return browse;
    final direct = _data[path];
    if (direct is Map &&
        !uri.path.contains('/meal-plan/ingredients') &&
        !uri.path.contains('/meal-plan/pairings/')) {
      final result = _copy(direct);
      final options =
          _data['snapshot-options:${uri.pathSegments.length > 1 ? uri.pathSegments[1] : ''}'];
      if (result['recipe'] is Map && options is Map) {
        final recipe = result['recipe'] as Map;
        final editOptions = _copy(
          uri.path.endsWith('/recipe-blank') && recipe['edit_options'] is Map
              ? recipe['edit_options'] as Map
              : options,
        );
        final choices = <String, dynamic>{
          for (final choice in editOptions['recipes'] as List? ?? [])
            '${choice['id']}': choice,
          for (final row in _data.entries)
            if (row.key.startsWith(
                  '/households/${uri.pathSegments[1]}/recipes/',
                ) &&
                Uri.parse(row.key).pathSegments.length == 4 &&
                row.value is Map &&
                row.value['recipe'] is Map)
              '${row.value['recipe']['id']}': {
                'id': row.value['recipe']['id'],
                'title': row.value['recipe']['title'],
              },
          for (final field in ['related', 'pairings', 'variation_family'])
            for (final choice in recipe[field] as List? ?? [])
              '${choice['id']}': {'id': choice['id'], 'title': choice['title']},
        }..remove('${recipe['id']}');
        editOptions['recipes'] = choices.values.toList();
        recipe['edit_options'] = editOptions;
      }
      return uri.path.endsWith('/meal-plan')
          ? _filterPlan(result, uri)
          : result;
    }
    final parts = uri.pathSegments;
    if (parts.length == 5 &&
        parts[2] == 'meal-plan' &&
        parts[3] == 'pairings') {
      final recipe =
          (await cached(
                '/households/${parts[1]}/recipes/${parts[4]}',
              ))?['recipe']
              as Map?;
      if (recipe != null) {
        final pairings = recipe['pairings'] as List? ?? [];
        return {
          'recipes': pairings.where((p) => p['in_household'] != false).toList(),
        };
      }
    }
    if (parts.length == 4 &&
        parts[2] == 'meal-plan' &&
        parts[3] == 'ingredients') {
      final plan = _data['/households/${parts[1]}/meal-plan'] as Map?;
      if (plan != null) {
        final rows = <Map<String, dynamic>>[];
        final blanks = <String, Map<String, dynamic>>{};
        final range = _filterPlan(plan, uri);
        for (final meal in range['entries'] as List) {
          if (meal['kind'] != 'recipe' || meal['plan_date'] == null) continue;
          if (meal['available'] == false) {
            throw ApiException(
              409,
              'A planned recipe is unavailable. Update the plan before collecting ingredients.',
            );
          }
          final recipe =
              (await cached(
                    '/households/${parts[1]}/recipes/${meal['recipe_id']}',
                  ))?['recipe']
                  as Map?;
          if (recipe == null) return null;
          if (recipe['source_type'] == 'blank') {
            blanks['${recipe['id']}'] = {
              'id': recipe['id'],
              'title': recipe['title'],
            };
          }
          for (final ingredient in recipe['ingredients'] as List? ?? []) {
            rows.add({
              ...Map<String, dynamic>.from(ingredient as Map),
              'meal_entry_id': meal['id'],
              'plan_date': meal['plan_date'],
              'recipe_title': recipe['title'],
            });
          }
        }
        return {'ingredients': rows, 'blank_recipes': blanks.values.toList()};
      }
    }
    if (parts.length == 4 && parts[2] == 'recipes' && _data[uri.path] is Map) {
      return _copy(_data[uri.path] as Map);
    }
    if (parts.length == 5 &&
        parts[2] == 'recipes' &&
        parts[4] == 'edit-options') {
      final detailPath = '/${parts.take(4).join('/')}';
      final recipe = ((await cached(detailPath))?['recipe']) as Map?;
      if (recipe?['edit_options'] is Map) {
        return {'edit_options': _copy(recipe!['edit_options'] as Map)};
      }
    }
    if (parts.length == 3 && parts[2] == 'meal-plan') {
      final state = _data[uri.path] as Map?;
      if (state != null) return _filterPlan(state, uri);
    }
    return null;
  }

  Map<String, dynamic>? _snapshotBrowse(Uri uri) {
    final parts = uri.pathSegments;
    if (parts.length != 3 ||
        parts[2] != 'recipes' ||
        _data['snapshot-version:${parts[1]}'] == null) {
      return null;
    }
    final categories = _data['snapshot-categories:${parts[1]}'] as List;
    final root = uri.path;
    var rows = <Map<String, dynamic>>[
      for (final entry in _data.entries)
        if (entry.key.startsWith('$root/') &&
            Uri.parse(entry.key).pathSegments.length == 4 &&
            entry.value is Map &&
            entry.value['recipe'] is Map)
          {
            ...Map<String, dynamic>.from(entry.value['recipe'] as Map),
            'photo_url': localRecipeCover(entry.value['recipe'] as Map),
          },
    ];
    final known = rows.map((r) => '${r['id']}').toSet();
    String representative(Map row) {
      final id =
          '${row['family_representative_id'] ?? row['parent_recipe_id'] ?? row['id']}';
      return known.contains(id) ? id : '${row['id']}';
    }

    final categoryById = <String, Map>{
      for (final category in categories) '${category['id']}': category as Map,
    };
    final membership = <String, Set<String>>{};
    for (final row in rows) {
      final ids = <String>{};
      for (final assignment in row['category_assignments'] as List? ?? []) {
        String? id = '${assignment['category_id']}';
        while (id != null && ids.add(id)) {
          final parent = categoryById[id]?['parent_id'];
          id = parent == null ? null : '$parent';
        }
      }
      membership['${row['id']}'] = ids;
    }
    bool inCategory(Map row, String category) =>
        membership['${row['id']}']!.contains(category);

    final q = (uri.queryParameters['q'] ?? '').toLowerCase();
    final scope = uri.queryParameters['scope'] ?? '';
    final favorites = uri.queryParameters['favorite_people'];
    final blank = uri.queryParameters['blank'] == '1';
    final families =
        uri.queryParameters['families'] == '1' && favorites == null && !blank;
    if (uri.queryParameters['tree'] == '1' &&
        q.isEmpty &&
        favorites == null &&
        !blank &&
        (scope.isEmpty ||
            categories.any(
              (c) => c['id'] == scope && c['parent_id'] == null,
            ))) {
      return {
        'view': 'categories',
        'recipes': [],
        'next_offset': null,
        'category_nodes': [
          for (final category in categories)
            if ((category['parent_id'] ?? '') == scope &&
                (scope.isEmpty ||
                    rows.any((r) => inCategory(r, '${category['id']}'))))
              {
                ...Map<String, dynamic>.from(category as Map),
                'needs_ai_image': false,
                'recipe_count': families
                    ? rows
                          .where((r) => inCategory(r, '${category['id']}'))
                          .map(representative)
                          .toSet()
                          .length
                    : rows
                          .where((r) => inCategory(r, '${category['id']}'))
                          .length,
              },
        ],
      };
    }
    rows = rows.where((row) {
      if (scope.isNotEmpty && !inCategory(row, scope)) return false;
      if (blank && row['source_type'] != 'blank') return false;
      if (favorites != null) {
        final people =
            (_data['$root/${row['id']}/favorites'] as Map?)?['people']
                as List? ??
            [];
        if (!favorites
            .split(',')
            .every(
              (id) => people.any(
                (p) => '${p['id']}' == id && p['favorite'] == true,
              ),
            )) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      return [
        row['title'],
        row['description'],
        for (final i in row['ingredients'] as List? ?? []) i['ingredient_name'],
        for (final t in row['tags'] as List? ?? []) t['label'],
        for (final id in membership['${row['id']}']!)
          categoryById[id]?['label'],
      ].join(' ').toLowerCase().contains(q);
    }).toList();
    if (families) {
      final ids = rows.map(representative).toSet();
      rows = [
        for (final id in ids)
          Map<String, dynamic>.from(
            (_data['$root/$id'] as Map)['recipe'] as Map,
          ),
      ];
    }
    rows.sort((a, b) {
      final title = '${a['title']}'.toLowerCase().compareTo(
        '${b['title']}'.toLowerCase(),
      );
      return title != 0 ? title : '${a['id']}'.compareTo('${b['id']}');
    });
    final offset = int.tryParse(uri.queryParameters['offset'] ?? '0') ?? 0;
    return {
      'view': 'recipes',
      'recipes': rows.skip(offset).take(30).toList(),
      'category_nodes': [],
      'next_offset': offset + 30 < rows.length ? offset + 30 : null,
    };
  }

  Map<String, dynamic> _filterPlan(Map state, Uri uri) {
    final result = _copy(state);
    for (final entry in (result['entries'] as List? ?? [])) {
      if (entry['kind'] == 'recipe') {
        final recipe =
            (_data['/households/${uri.pathSegments[1]}/recipes/${entry['recipe_id']}']
                    as Map?)?['recipe']
                as Map?;
        if (recipe != null) {
          entry['photo_url'] = localRecipeCover(recipe) ?? entry['photo_url'];
        }
      }
    }
    final from = uri.queryParameters['from'], to = uri.queryParameters['to'];
    result['entries'] = (result['entries'] as List? ?? []).where((e) {
      final date = e['plan_date'] as String?;
      return date == null ||
          (from == null || date.compareTo(from) >= 0) &&
              (to == null || date.compareTo(to) <= 0);
    }).toList();
    return result;
  }

  bool ownsWrite(String path) =>
      RegExp(
        r'^/households/[^/]+/(recipes(?:/[^/]+(?:/(?:favorites|delete|restore|attach))?)?|meal-plan|shopping-list(?:/photos)?|restaurants|name|people/me/name)$',
      ).hasMatch(Uri.parse(path).path) ||
      path == '/me/name' ||
      path.startsWith('/me/cooking-sessions');

  Future<Map<String, dynamic>> save(
    String input,
    Map<String, dynamic> value,
  ) async {
    final wasConnected = connected();
    late Map<String, dynamic> result;
    await _serial(() async {
      await _load();
      final path = _path(input);
      final body = _copy(value)
        ..remove('household_count')
        ..remove('revision')
        ..remove('_offline_pending')
        ..remove('_local_pending');
      final beforePending = _pending.map(_copy).toList();
      if (path.endsWith('/shopping-list') && body['items'] is List) {
        final current = (_data[path] as Map?)?['items'] as List? ?? [];
        final items = body.remove('items') as List;
        final old = {for (final item in current) item['id']: item};
        body['upsert_items'] = [
          for (final item in items)
            if (jsonEncode(old[item['id']]) != jsonEncode(item)) item,
        ];
        body['remove_ids'] = [
          for (final item in current)
            if (!items.any((next) => next['id'] == item['id'])) item['id'],
        ];
        if ((body['remove_ids'] as List).isEmpty) body.remove('remove_ids');
        if (jsonEncode(current.map((e) => e['id']).toList()) !=
            jsonEncode(items.map((e) => e['id']).toList())) {
          body['order'] = items.map((e) => e['id']).toList();
        }
      }

      final photo = path.endsWith('/shopping-list/photos');
      final recipe = RegExp(r'^/households/[^/]+/recipes(?:/[^/]+)?$')
          .hasMatch(path);
      final creating = recipe && Uri.parse(path).pathSegments.length == 3;
      final priorCreate = _pending
          .where(
            (e) =>
                e['local_id'] != null &&
                path == '${e['path']}/${e['local_id']}',
          )
          .firstOrNull;
      final entry = <String, dynamic>{
        'id': body['operation_id'] ?? newId(),
        'path': path,
        'body': body,
        'review':
            !wasConnected &&
            (path.endsWith('/meal-plan') ||
                (recipe && !creating && priorCreate == null)),
        if (creating) 'local_id': 'local-${newId()}',
        if (photo) 'local_photo': newId() + newId(),
        if (body['remove_ids'] is List)
          'expires': now().add(const Duration(hours: 2)).millisecondsSinceEpoch,
      };
      if (creating) body['client_save_id'] = entry['id'];
      if (recipe && !creating) body.remove('client_save_id');
      if (body['_local_recipe'] is Map) {
        entry['recipe'] = body.remove('_local_recipe');
      }
      if (path.endsWith('/meal-plan') && body['operation'] != 'add') {
        final meal =
            ((_data[path] as Map?)?['entries'] as List? ?? [])
                    .where((e) => e['id'] == body['id'])
                    .firstOrNull
                as Map?;
        if (meal != null) {
          entry['meal'] = _copy(meal);
          for (final field in ['kind', 'recipe_id', 'restaurant_id']) {
            if (meal[field] != null) body[field] = meal[field];
          }
        }
      }
      if (path.endsWith('/delete')) {
        final detail = path.substring(0, path.length - 7);
        entry['deleted_recipe'] = _data[detail];
        _pending.removeWhere((e) => e['path'] == detail && e['review'] == true);
      }
      entry['description'] = _describe(entry);
      if (recipe && !creating && priorCreate == null) {
        _pending.removeWhere((e) => e['path'] == path);
      }
      if (path.endsWith('/meal-plan')) {
        _pending.removeWhere(
          (e) => e['path'] == path && e['body']['id'] == body['id'],
        );
      }
      _pending.add(entry);
      try {
        await _commit(_server, path);
      } catch (_) {
        _pending
          ..clear()
          ..addAll(beforePending);
        _rebuild();
        rethrow;
      }
      result = photo
          ? {'photo': entry['local_photo']}
          : recipe
          ? {
              'recipe': _copy(
                (_data[creating ? '$path/${entry['local_id']}' : path]
                        as Map)['recipe']
                    as Map,
              ),
            }
          : _copy(_data[path] as Map? ?? {'saved': true});
      result['_local_pending'] = true;
      if (!wasConnected && recipe) {
        result['_offline_pending'] = true;
        (result['recipe'] as Map)['_offline_pending'] = true;
      }
    });
    if (connected()) unawaited(synchronize());
    return result;
  }

  String _describe(Map entry) {
    final path = entry['path'] as String, body = entry['body'] as Map;
    if (!path.endsWith('/meal-plan')) {
      return 'Changes to “${body['title'] ?? 'recipe'}”';
    }
    final rows = (_data[path] as Map?)?['entries'] as List? ?? [];
    final previous =
        rows.where((e) => e['id'] == body['id']).firstOrNull as Map?;
    final household = Uri.parse(path).pathSegments[1];
    final title =
        previous?['title'] ??
        (_data['/households/$household/recipes/${body['recipe_id']}']
            as Map?)?['recipe']?['title'] ??
        body['title'] ??
        (body['kind'] == 'leftovers' ? 'Leftovers' : 'Restaurant');
    return switch (body['operation']) {
      'move' => 'Move $title from ${previous?['plan_date']} to ${body['date']}',
      'remove' => 'Remove $title from ${previous?['plan_date']}',
      _ => 'Add $title on ${body['date']}',
    };
  }

  bool _resolveRecipeIds(dynamic value, Map aliases) {
    var resolved = true;
    if (value is Map) {
      for (final field in value.keys.toList()) {
        if ([
          'recipe_id',
          'parent_recipe_id',
          'paired_recipe_id',
        ].contains(field)) {
          if (aliases.containsKey(value[field])) {
            value[field] = aliases[value[field]];
          }
          if ('${value[field]}'.startsWith('local-')) resolved = false;
        } else if (!_resolveRecipeIds(value[field], aliases)) {
          resolved = false;
        }
      }
    } else if (value is List) {
      for (final child in value) {
        if (!_resolveRecipeIds(child, aliases)) resolved = false;
      }
    }
    return resolved;
  }

  void _apply(Map<String, dynamic> data, Map entry) {
    final aliases = data['local-aliases'] as Map? ?? {};
    var path = entry['path'] as String;
    for (final alias in aliases.entries) {
      path = path.replaceAll(
        '/recipes/${alias.key}',
        '/recipes/${alias.value}',
      );
    }
    final body = _copy(entry['body'] as Map);
    _resolveRecipeIds(body, aliases);
    final parts = Uri.parse(path).pathSegments;
    if (path.startsWith('/me/cooking-sessions')) {
      const root = '/me/cooking-sessions';
      final state = _copy(data[root] as Map? ?? {'sessions': []});
      final rows = List<dynamic>.from(state['sessions'] as List);
      final creating = path == root;
      final id = creating ? body['session_id'] : parts[2];
      var session = rows.where((e) => e['id'] == id).firstOrNull as Map?;
      if (creating && session == null) {
        session = {
          'id': id,
          'household_id': body['household_id'],
          'recipe': entry['recipe'],
          'completed': [],
          'timers': [],
          'joined_devices': [body['installation_id']],
          'owned': true,
          'invited': false,
          'open_elsewhere': false,
          'ended_at': null,
        };
        rows.add(session);
      }
      if (session != null) {
        final action = creating ? 'create' : parts.last;
        if (action == 'end') {
          session['ended_at'] = now().millisecondsSinceEpoch;
          rows.remove(session);
        }
        if (action == 'join') {
          session['joined_devices'] = {
            ...session['joined_devices'] as List,
            body['installation_id'],
          }.toList();
        }
        if (session['combined'] == true) {
          if (action == 'start' ||
              (action == 'step' && body['checked'] == true)) {
            session['started_at'] ??= now().millisecondsSinceEpoch;
          }
          if (action == 'dinner') session['dinner_at'] = body['dinner_at'];
        }
        if (action == 'step') {
          final done = List<dynamic>.from(session['completed'] as List)
            ..remove(body['step_id']);
          if (body['checked'] == true) done.add(body['step_id']);
          session['completed'] = done;
        }
        if (action == 'timer') {
          final timers = List<dynamic>.from(session['timers'] as List);
          final old =
              timers
                      .where((e) => e['action_id'] == body['action_id'])
                      .firstOrNull
                  as Map?;
          timers.removeWhere((e) => e['action_id'] == body['action_id']);
          final recipe = session['recipe'] as Map;
          final named = (recipe['actions'] as List? ?? [])
              .where((e) => '${e['id']}' == '${body['action_id']}')
              .firstOrNull;
          timers.add({
            ...?old,
            ...body,
            'timer_id': 'session:$id:${body['action_id']}',
            'session_id': id,
            'title':
                '${recipe['title']} · ${named?['label'] ?? 'Cooking timer'}',
            'deadline_ms':
                body['deadline_ms'] ??
                old?['deadline_ms'] ??
                now().millisecondsSinceEpoch,
          });
          session['timers'] = timers;
        }
      }
      state['sessions'] = rows;
      data[root] = state;
      data[path] = {
        if (creating) 'sessions': rows,
        'session':
            session ?? {'id': id, 'ended_at': now().millisecondsSinceEpoch},
      };
    } else if (path.endsWith('/shopping-list/photos')) {
      final id =
          (data['photo-aliases'] as Map?)?[entry['local_photo']] ??
          entry['local_photo'];
      data['$path/$id'] = {'image_base64': body['image_base64']};
    } else if (path.endsWith('/shopping-list') ||
        path.endsWith('/restaurants')) {
      final state = _copy(
        data[path] as Map? ??
            {
              'items': [],
              'departments': ['Other'],
              'revision': 0,
            },
      );
      if (body['items'] is List) {
        state['items'] = body['items'];
        final photos = data['photo-aliases'] as Map? ?? {};
        for (final item in state['items'] as List) {
          if (photos.containsKey(item['photo'])) {
            item['photo'] = photos[item['photo']];
          }
        }
      }
      if (body['upsert_items'] is List) {
        final rows = List<dynamic>.from(state['items'] as List);
        for (final item in body['upsert_items'] as List) {
          final index = rows.indexWhere((old) => old['id'] == item['id']);
          if (index < 0) {
            rows.add(item);
          } else {
            rows[index] = item;
          }
        }
        state['items'] = rows;
      }
      if (body['order'] is List) {
        final order = body['order'] as List;
        (state['items'] as List).sort((a, b) {
          final ai = order.indexOf(a['id']), bi = order.indexOf(b['id']);
          return (ai < 0 ? order.length : ai).compareTo(
            bi < 0 ? order.length : bi,
          );
        });
      }
      if (body['departments'] is List) {
        state['departments'] = body['departments'];
      }
      if (body['remove_ids'] is List) {
        state['items'] = (state['items'] as List)
            .where((e) => !(body['remove_ids'] as List).contains(e['id']))
            .toList();
      }
      data[path] = state;
    } else if (path.endsWith('/meal-plan')) {
      final state = _copy(data[path] as Map? ?? {'entries': [], 'revision': 0});
      final rows = List<dynamic>.from(state['entries'] as List);
      final previous =
          (rows.where((e) => e['id'] == body['id']).firstOrNull ??
                  entry['meal'])
              as Map?;
      rows.removeWhere((e) => e['id'] == body['id']);
      if (body['operation'] != 'remove') {
        final recipe =
            (data['/households/${parts[1]}/recipes/${body['recipe_id']}']
                    as Map?)?['recipe']
                as Map?;
        final restaurant =
            ((data['/households/${parts[1]}/restaurants'] as Map?)?['items']
                        as List? ??
                    [])
                .where((e) => e['id'] == body['restaurant_id'])
                .firstOrNull;
        rows.add({
          ...?previous,
          if (body['operation'] == 'add') ...body,
          'id': body['id'],
          'plan_date': body['date'],
          if (body['operation'] == 'add')
            'title':
                recipe?['title'] ??
                restaurant?['name'] ??
                (body['kind'] == 'leftovers' ? 'Leftovers' : 'Restaurant'),
          if (recipe != null) 'photo_url': localRecipeCover(recipe),
          'available': true,
        });
      }
      state['entries'] = rows;
      data[path] = state;
    } else if (parts.length >= 3 && parts[2] == 'recipes') {
      final root = '/${parts.take(3).join('/')}';
      if (parts.last == 'delete') {
        final detail = '/${parts.take(4).join('/')}';
        final old = (data.remove(detail) ?? entry['deleted_recipe']) as Map?;
        if (old != null) data['deleted:$detail'] = old;
        final deleted = _copy(
          data['$root/deleted'] as Map? ?? {'recipes': [], 'next_offset': null},
        );
        (deleted['recipes'] as List).removeWhere(
          (r) => '${r['id']}' == parts[3],
        );
        if (old?['recipe'] is Map) {
          (deleted['recipes'] as List).add({
            ...old!['recipe'] as Map,
            'deleted_at': now().toIso8601String(),
          });
        }
        data['$root/deleted'] = deleted;
        data[path] = {
          'purge_after':
              ((old?['recipe'] as Map?)?['household_count'] as num? ?? 1) > 1
              ? null
              : now().add(const Duration(days: 30)).toIso8601String(),
        };
      } else if (parts.last == 'restore') {
        final detail = '/${parts.take(4).join('/')}';
        final old = data['deleted:$detail'];
        if (old != null) data[detail] = _copy(old as Map);
        final deleted = data['$root/deleted'] as Map?;
        (deleted?['recipes'] as List?)?.removeWhere(
          (r) => '${r['id']}' == parts[3],
        );
      } else if (parts.last == 'attach') {
        final detail = '/${parts.take(4).join('/')}';
        final recipe =
            (data['deleted:$detail'] as Map?)?['recipe'] ??
            body['recipe'] ??
            (data[detail] as Map?)?['recipe'];
        if (recipe is Map) {
          data[detail] = {
            'recipe': {...recipe, 'in_household': true},
          };
          data[path] = data[detail];
        }
      } else if (parts.last == 'favorites') {
        final state = _copy(data[path] as Map? ?? {'people': []});
        for (final p in state['people'] as List) {
          if (p['id'] == body['person_id']) p['favorite'] = body['favorite'];
        }
        data[path] = state;
      } else if (parts.length == 3 || parts.length == 4) {
        final id = parts.length == 3
            ? '${aliases[entry['local_id']] ?? entry['local_id']}'
            : parts[3];
        final detail = '$root/$id';
        final old = (data[detail] as Map?)?['recipe'] as Map? ?? {};

        final favorites = '$detail/favorites';
        if (data[favorites] == null) {
          final people =
              (data['/households/${parts[1]}/people'] as Map?)?['people']
                  as List? ??
              [];
          final user = (data['/me'] as Map?)?['user']?['id'];
          final current = people.where((p) => p['user_id'] == user).firstOrNull;
          data[favorites] = {
            'people': [
              for (final p in people)
                {
                  ...p as Map,
                  'favorite': (body['favorite_people'] as List? ?? []).any(
                    (f) => f['person_id'] == p['id'] && f['favorite'] == true,
                  ),
                },
            ],
            'current_person_id': current?['id'],
          };
        }
        data[detail] = {
          'recipe': {
            ...old,
            ...body,
            'id': id,
            'in_household': true,
            'household_count': old['household_count'] ?? 1,
          },
        };
      }
      for (final key
          in data.keys.where((k) => k.startsWith('$root?')).toList()) {
        data.remove(key);
      }
    } else if (path == '/me/name') {
      final account = data['/me'] as Map?;
      if (account != null) {
        (account['user'] as Map)['display_name'] = body['display_name'];
      }
      data[path] = {
        'user': {
          ...?account?['user'] as Map?,
          'display_name': body['display_name'],
        },
      };
    } else if (parts.length == 5 &&
        parts[2] == 'people' &&
        parts[3] == 'me' &&
        parts[4] == 'name') {
      final people =
          (data['/households/${parts[1]}/people'] as Map?)?['people']
              as List? ??
          [];
      final user = (data['/me'] as Map?)?['user']?['id'];
      final person =
          people.where((p) => p['user_id'] == user).firstOrNull as Map?;
      if (person != null) person['display_name'] = body['display_name'];
      data[path] = {'person': person ?? body};
    } else if (parts.length == 3 && parts.last == 'name') {
      final account = data['/me'] as Map?;
      for (final h in account?['households'] as List? ?? []) {
        if ('${h['id']}' == parts[1]) h['name'] = body['name'];
      }
      data[path] = {
        'household': {'id': parts[1], ...body},
      };
    }
  }

  Future<void> expire() => _serial(() async {
    await _load();
    final before = _pending.length;
    _pending.removeWhere(
      (e) =>
          e['expires'] is int &&
          (e['expires'] as int) <= now().millisecondsSinceEpoch,
    );
    if (before != _pending.length) await _commit(_server, '/me');
  });
  Duration? get untilRemovalExpiry {
    final times = _pending
        .where((e) => e['expires'] is int)
        .map((e) => e['expires'] as int);
    if (times.isEmpty) return null;
    return Duration(
      milliseconds: max(0, times.reduce(min) - now().millisecondsSinceEpoch),
    );
  }

  Future<void> decide(String id, bool submit) => _serial(() async {
    await _load();
    final entry = _pending.where((e) => e['id'] == id).firstOrNull;
    if (entry == null) return;
    final before = _pending.map(_copy).toList();
    if (submit) {
      entry['review'] = false;
      if (entry['confirmation'] == 'shared_confirmation_required') {
        entry['body']['confirm_shared_edit'] = true;
      }
      if (entry['confirmation'] == 'past_confirmation_required') {
        entry['body']['confirm_past'] = true;
      }
      entry.remove('confirmation');
    } else {
      _pending.remove(entry);
    }
    try {
      await _commit(_server, entry['path'] as String);
    } catch (_) {
      _pending
        ..clear()
        ..addAll(before);
      _rebuild();
      rethrow;
    }
    if (submit && connected()) unawaited(synchronize());
  });

  String _deliveryKey(Map entry) {
    var path = entry['path'] as String;
    for (final alias in (_data['local-aliases'] as Map? ?? {}).entries) {
      path = path.replaceAll(
        '/recipes/${alias.key}',
        '/recipes/${alias.value}',
      );
    }
    if (entry['local_id'] != null) return '$path/${entry['local_id']}';
    if (path.endsWith('/meal-plan')) return '$path#${entry['body']['id']}';
    if (path.startsWith('/me/cooking-sessions')) {
      final parts = Uri.parse(path).pathSegments;
      return '/me/cooking-sessions/${parts.length == 2 ? entry['body']['session_id'] : parts[2]}';
    }
    return path;
  }

  Future<void> synchronize() async {
    await _load();
    await expire();
    if (_closed || !connected()) return;
    final paths = _pending
        .where((e) => e['review'] != true)
        .map(_deliveryKey)
        .toSet();
    await Future.wait(paths.map(_deliver));
  }

  Future<void> _deliver(String lane) async {
    if (!_sending.add(lane)) return;
    try {
      while (!_closed && connected()) {
        final entry = _pending
            .where((e) => _deliveryKey(e) == lane)
            .firstOrNull;
        if (entry == null) break;
        final path = entry['path'] as String;
        if (entry['review'] == true || !_accessible(path)) {
          break;
        }
        final body = _copy(entry['body'] as Map);
        final aliases = _data['local-aliases'] as Map? ?? {};
        final resolved = _resolveRecipeIds(body, aliases);
        var target = path;
        for (final alias in aliases.entries) {
          target = target.replaceAll(
            '/recipes/${alias.key}',
            '/recipes/${alias.value}',
          );
        }
        if (target.contains('/local-') || !resolved) {
          break;
        }
        final photos = _data['photo-aliases'] as Map? ?? {};
        var waitingForPhoto = false;
        for (final item
            in (body['upsert_items'] ?? body['items']) as List? ?? []) {
          if (photos.containsKey(item['photo'])) {
            item['photo'] = photos[item['photo']];
          }
          if (item['photo'] != null &&
              _pending.any((e) => e['local_photo'] == item['photo'])) {
            waitingForPhoto = true;
          }
        }
        if (waitingForPhoto) break;
        try {
          final reply = await send(target, body);
          await _serial(() async {
            if (!_pending.contains(entry)) return;
            if (entry['local_id'] != null && reply['recipe'] is Map) {
              final id = '${(reply['recipe'] as Map)['id']}';
              _server['local-aliases'] = {
                ...?_server['local-aliases'] as Map?,
                entry['local_id']: id,
              };
              if (_server['$path/$id'] == null) {
                _server['$path/$id'] = {'recipe': reply['recipe']};
              }
            }
            if (entry['local_photo'] != null && reply['photo'] is String) {
              _server['photo-aliases'] = {
                ...?_server['photo-aliases'] as Map?,
                entry['local_photo']: reply['photo'],
              };
              _server['$path/${reply['photo']}'] = {
                'image_base64': body['image_base64'],
              };
            }
            final position = _pending.indexOf(entry);
            _pending.remove(entry);
            try {
              await _commit(_server, path);
            } catch (_) {
              _pending.insert(position, entry);
              _rebuild();
              rethrow;
            }

            onAcknowledged?.call(entry);
            if (entry['local_id'] != null ||
                entry['local_photo'] != null ||
                path == '/me/cooking-sessions') {
              scheduleMicrotask(() => unawaited(synchronize()));
            }
          });
        } catch (error) {
          if (!_pending.contains(entry)) continue;
          if (error is ApiException &&
              [
                'shared_confirmation_required',
                'past_confirmation_required',
              ].contains(error.code)) {
            await _serial(() async {
              entry['review'] = true;
              entry['confirmation'] = error.code;
              await _commit(_server, path);
            });
          }
          clientLog.record('sync', 'send_failed', path: target, error: error);
          onSendError?.call(path, error);
          break;
        }
      }
    } finally {
      _sending.remove(lane);
    }
  }

  void Function(String, Object)? onSendError;
  void Function(Map<String, dynamic>)? onAcknowledged;
  List<Map<String, dynamic>> get pendingChanges => _pending.map(_copy).toList();
  Future<void> importChanges(List<Map<String, dynamic>> changes) =>
      _serial(() async {
        await _load();
        for (final entry in changes) {
          if (!containsOperation(entry['id'] as String)) {
            _pending.add(_copy(entry));
          }
        }
        await _commit(_server, '/me');
      });
  bool containsOperation(String id) => _pending.any((e) => e['id'] == id);
  Future<void> acceptCooking(Map<String, dynamic> state) => _serial(() async {
    await _load();
    await _commit({
      ..._server,
      '/me/cooking-sessions': _copy(state),
    }, '/me/cooking-sessions');
  });

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
