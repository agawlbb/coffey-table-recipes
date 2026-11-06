import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'client_log.dart';
import 'offline_store.dart';

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
    final url = photo['source_url'] ?? photo['photo_url'];
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

/// A read cache of server state. It has no edit queue, conflict state or polling.
class LocalData extends ChangeNotifier {
  LocalData({
    required this.key,
    required this.fetch,
    required this.send,
    this.readStore = readOfflineStore,
    this.writeStore = writeOfflineStore,
  });
  final String key;
  final LocalRead fetch;
  final LocalWrite send;
  final Future<String?> Function(String) readStore;
  final Future<void> Function(String, String) writeStore;
  Map<String, dynamic> _data = {};
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
        _data = Map<String, dynamic>.from(
          (jsonDecode(text) as Map)['data'] as Map,
        );
      }
    } catch (error) {
      clientLog.record('storage', 'cache_read_failed', error: error);
      if (error is FormatException || error is TypeError) {
        _data = {};
        return;
      }
      _loaded = null;
      rethrow;
    }
  }();
  Future<void> _commit(Map<String, dynamic> data, String path) async {
    await writeStore('local-first-v1-$key', jsonEncode({'data': data}));
    _data = data;
    _generation++;
    if (!_closed) {
      notifyListeners();
      localDataChanges.value = '$path#${++_epoch}';
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
      final next = Map<String, dynamic>.from(_data);
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
  Future<void> installSnapshot(Map<String, dynamic> snapshot) =>
      _serial(() async {
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
              (responses['${prefix}recipes/${row['id']}'] as Map)['recipe']
                  is! Map,
        )) {
          throw const FormatException('Incomplete recipe snapshot');
        }
        final next = Map<String, dynamic>.from(_data);
        final shopping = next['${prefix}shopping-list'];
        next.removeWhere((path, _) => path.startsWith(prefix));
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
        await _commit({..._data, path: _copy(state)}, path);
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
            Map<String, dynamic>.from(_data)..removeWhere(
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
          ..._data,
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
      if (result['recipe'] is Map &&
          options is Map &&
          !uri.path.endsWith('/recipe-blank')) {
        final recipe = result['recipe'] as Map;
        final editOptions = _copy(options);
        final choices = <String, dynamic>{
          for (final choice in editOptions['recipes'] as List? ?? [])
            '${choice['id']}': choice,
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
          Map<String, dynamic>.from(entry.value['recipe'] as Map),
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

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
