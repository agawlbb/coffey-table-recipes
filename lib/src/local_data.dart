import 'child_mode.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'shopping_changes.dart';
import 'offline_store.dart';
import 'shopping_item_id.dart';

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

Map<String, dynamic> _copy(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

String describeLocalData(Map value) {
  final data = value['recipe'] as Map? ?? value;
  final lines = <String>[];
  for (final field in ['title', 'description', 'notes']) {
    if (data[field] != null && '${data[field]}'.isNotEmpty) {
      lines.add('${data[field]}');
    }
  }
  if (data['operation'] != null) {
    lines.add('${data['operation']} meal · ${data['date'] ?? 'Missing date'}');
  }
  for (final row in data['items'] as List? ?? []) {
    lines.add('${row['checked'] == true ? '☑' : '☐'} ${row['name']}');
  }
  for (final row in data['ingredients'] as List? ?? []) {
    lines.add('${row['original_text'] ?? row['ingredient_name'] ?? ''}');
  }
  for (final row in data['steps'] as List? ?? []) {
    lines.add('${row['instruction'] ?? ''}');
  }
  for (final row in data['entries'] as List? ?? []) {
    lines.add(
      '${row['plan_date'] ?? 'Missing date'} · ${row['title'] ?? row['kind']}',
    );
  }
  for (final row in data['recipes'] as List? ?? []) {
    lines.add('${row['title']}');
  }
  return lines.isEmpty ? 'No entries.' : lines.join('\n\n');
}

/// Durable account/server-scoped mirror and transactional outbox. Local writes
/// complete only after persistence. Network requests are serialized separately.
class LocalData extends ChangeNotifier {
  static void _remapChildren(Map body, Map<String, Map<String, String>> ids) {
    for (final field in [
      'ingredients',
      'groups',
      'steps',
      'actions',
      'photos',
    ]) {
      for (final row in body[field] as List? ?? []) {
        final mapped = ids[field]?['${row['id']}'];
        if (mapped != null) row['id'] = mapped;
        if (field == 'ingredients' &&
            ids['groups']?['${row['group_id']}'] != null) {
          row['group_id'] = ids['groups']!['${row['group_id']}'];
        }
        if (field == 'actions' && ids['steps']?['${row['step_id']}'] != null) {
          row['step_id'] = ids['steps']!['${row['step_id']}'];
        }
      }
    }
  }

  LocalData({
    required this.key,
    required this.fetch,
    required this.send,
    this.readServer,
    this.fallback,
    this.onRecipeSaved,
    this.online,
    this.snapshotOnly = false,
    this.onPendingChanged,
    this.now = DateTime.now,
    this.readStore = readOfflineStore,
    this.writeStore = writeOfflineStore,
  });

  final Future<void> Function(String scope, List<Map<String, dynamic>> changes)?
  onPendingChanged;
  final DateTime Function() now;
  final String key;
  final bool snapshotOnly;
  final LocalRead fetch;
  final LocalRead? readServer;
  final LocalWrite send;
  final Future<Map<String, dynamic>?> Function(String)? fallback;
  final Future<void> Function(String, Map<String, dynamic>)? onRecipeSaved;
  final bool Function()? online;
  final Future<String?> Function(String) readStore;
  final Future<void> Function(String, String) writeStore;
  Map<String, dynamic> _data = {}, _aliases = {}, _blocked = {};
  List<Map<String, dynamic>> _queue = [], _archive = [];
  final _inflight = <String, Future<Map<String, dynamic>>>{};
  final _attempted = <String, DateTime>{};
  final _watched = <String, String>{};
  final _versions = <String, int>{};
  Future<void>? _ready, _draining;
  Future<void> _disk = Future.value(), _edits = Future.value();
  Timer? _timer, _reminderTimer;
  Future<void> _reminders = Future.value();
  String? reminderError;
  int? _serverOffsetMs;
  int _lastShoppingEditMs = 0;
  void observeServerTime(int milliseconds, DateTime receivedAt) {
    _serverOffsetMs = milliseconds - receivedAt.millisecondsSinceEpoch;
    if (_lastShoppingEditMs > milliseconds + 300000) {
      _lastShoppingEditMs = milliseconds;
    }
  }

  int get overdue => _queue
      .where(
        (q) =>
            now().millisecondsSinceEpoch >=
            (q['saved_at'] as int? ?? now().millisecondsSinceEpoch) + 60000,
      )
      .length;
  bool _closed = false;
  int _epoch = 0;
  int _accessEpoch = 0;
  String? error;
  int get snapshotEpoch => _epoch;
  int get pending => _queue.length;
  String? get lastSyncFailure {
    final failed = _queue.where((q) => q['last_error'] != null).toList()
      ..sort(
        (a, b) => (b['last_attempt_at'] as int).compareTo(
          a['last_attempt_at'] as int,
        ),
      );
    if (failed.isEmpty) return null;
    final q = failed.first;
    return '${q['last_status'] == null ? '' : 'HTTP ${q['last_status']}: '}${q['last_error']}';
  }

  List<Map<String, dynamic>> get conflicts =>
      _queue.where((q) => q['problem'] != null).map(_copy).toList();
  List<Map<String, dynamic>> get archivedDrafts => _archive.map(_copy).toList();

  Future<Map<String, dynamic>?> cachedView(String path) async {
    _watch(path);
    final saved = await cached(path);
    if (!snapshotOnly && saved != null && !_dirty(path)) {
      unawaited(refresh(path).catchError((Object _) => saved));
    }
    return saved;
  }

  /// The backend's blank-recipe endpoint returns an unsaved editor template.
  /// Mirror its catalog so creating an ordinary recipe also works offline.
  Future<Map<String, dynamic>> blank(
    String path, {
    bool refresh = false,
  }) async {
    await _load();
    if (_blocked.keys.any((prefix) => _under(path, prefix))) {
      throw ApiException(403, 'Access to this household was removed.');
    }
    if (!refresh && _data[path] is Map) return _copy(_data[path] as Map);
    final template = await send(path, {});
    _data[path] = _copy(template);
    await _persist();
    return _copy(template);
  }

  void inventoryUpdated(String household) {
    final root = '/households/$household/recipes';
    _data.removeWhere(
      (path, _) =>
          path.startsWith(root) &&
          Uri.parse(path).pathSegments.length <= 4 &&
          !_dirty(path) &&
          !_aliases.values.any((id) => path == '$root/$id'),
    );
    _bump(root);
    _changed(root);
  }

  /// Online-only delete/restore/attach actions must update the same local source
  /// as ordinary edits, rather than leaving a stale second copy on screen.
  Future<void> acceptServerRecipe(
    String path,
    Map<String, dynamic> result,
  ) async {
    await _serial(() async {
      await _load();
      final parts = Uri.parse(path).pathSegments;
      if (parts.length < 3 || parts[2] != 'recipes') return;
      final root = '/${parts.take(3).join('/')}';
      final recipe = result['recipe'] as Map?;
      final id = result['deleted_recipe_id'] ?? recipe?['id'];
      if (id == null) return;
      _data.removeWhere((p, _) => Uri.parse(p).path == root);
      final detail = '$root/$id';
      if (result['deleted_recipe_id'] != null) {
        _data.removeWhere((p, _) => _under(p, detail));
        _blocked[detail] = 404;
        final related = _queue
            .where((q) => _under(q['path'] as String, detail))
            .toList();
        _archive.addAll(related.map(_copy));
        _queue.removeWhere((q) => related.contains(q));
      } else if (recipe != null) {
        _blocked.remove(detail);
        _data[detail] = _copy(result);
      }
      await _persist();
      _bump(root);
      _changed(root);
    });
  }

  void _watch(String path) {
    final parts = Uri.parse(path).pathSegments;
    final group = parts.length >= 3 && parts[2] == 'recipes'
        ? '${parts[1]}-recipes-${parts.length == 3
              ? 'browse'
              : parts.length == 4
              ? 'detail'
              : parts.last}'
        : _resource(path);
    _watched[group] = path;
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _edits = _edits.then((_) async {
      try {
        done.complete(await action());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  String _path(String path) {
    for (final entry in _aliases.entries) {
      path = path.replaceAll('/${entry.key}', '/${entry.value}');
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

  Future<void> _load() => _ready ??= () async {
    final text = await readStore('local-first-v1-$key');
    if (text == null || text.isEmpty) return;
    try {
      final saved = jsonDecode(text) as Map;
      _data = Map<String, dynamic>.from(saved['data'] as Map);
      _aliases = Map<String, dynamic>.from(saved['aliases'] as Map? ?? {});
      _blocked = Map<String, dynamic>.from(saved['blocked'] as Map? ?? {});
      _serverOffsetMs ??= saved['server_offset_ms'] as int?;
      _lastShoppingEditMs = saved['last_shopping_edit_ms'] as int? ?? 0;
      _queue = (saved['queue'] as List).map((q) => _copy(q as Map)).toList();
      _archive = (saved['archive'] as List? ?? [])
          .map((q) => _copy(q as Map))
          .toList();
      for (final q in _queue) {
        q['saved_at'] ??= now().millisecondsSinceEpoch;
        if (q['sending'] == true &&
            (q['body'] as Map)['client_save_id'] == null &&
            (q['body'] as Map)['client_change_id'] == null) {
          q['problem'] = 'The app closed during synchronization. Review the server copy before retrying.';
        }
      }
      _updateReminders();
    } catch (_) {
      // Preserve the damaged source instead of silently overwriting edits.
      throw const FormatException(
        'Local data could not be read. Restore device storage before continuing.',
      );
    }
  }();

  Future<void> _persist({Map<String, dynamic>? data}) {
    final value = jsonEncode({
      'data': data ?? _data,
      'queue': _queue,
      'archive': _archive,
      'aliases': _aliases,
      'blocked': _blocked,
      'server_offset_ms': _serverOffsetMs,
      'last_shopping_edit_ms': _lastShoppingEditMs,
    });
    final task = _disk.then((_) async {
      await writeStore('local-first-v1-$key', value);
      _updateReminders();
    });
    _disk = task.catchError((Object _) {});
    return task;
  }

  void _updateReminders() {
    if (_closed) return;
    _reminderTimer?.cancel();
    final changes = [
      for (final q in _queue)
        {
          'id': q['id'],
          'deadline':
              (q['saved_at'] as int? ?? now().millisecondsSinceEpoch) + 60000,
        },
    ];
    final future =
        changes
            .map((q) => q['deadline'] as int)
            .where((t) => t > now().millisecondsSinceEpoch)
            .toList()
          ..sort();
    if (future.isNotEmpty) {
      _reminderTimer = Timer(
        Duration(
          milliseconds: (future.first - now().millisecondsSinceEpoch).clamp(
            0,
            60000,
          ),
        ),
        () {
          if (_closed) return;
          notifyListeners();
          _updateReminders();
        },
      );
    }
    final callback = onPendingChanged;
    if (callback != null) {
      _reminders = _reminders
          .then((_) => callback(key, changes))
          .then((_) {
            reminderError = null;
          })
          .catchError((Object _) {
            reminderError = 'Device notifications are unavailable. Pending changes remain visible here.';
            if (!_closed) notifyListeners();
          });
    }
  }

  void _changed(String path) {
    if (_closed) return;
    notifyListeners();
    // Notify outside build and use a distinct value for successive updates.
    scheduleMicrotask(() {
      if (!_closed) localDataChanges.value = '$path#${++_epoch}';
    });
  }

  bool mirrors(String path) =>
      path == '/me' ||
      RegExp(
        r'^/households/[^/]+/(recipes|people|shopping-list|restaurants|meal-plan)(/[^?]+)?(\?.*)?$',
      ).hasMatch(path);

  bool _under(String path, String prefix) {
    path = Uri.parse(path).path;
    return prefix == '/' ||
        (prefix.endsWith('/')
            ? path.startsWith(prefix)
            : path == prefix || path.startsWith('$prefix/'));
  }

  String _resource(String path) {
    final parts = Uri.parse(path).pathSegments;
    if (parts.length >= 3 && parts[2] == 'meal-plan') {
      return '/${parts.take(3).join('/')}';
    }
    return Uri.parse(path).path;
  }

  bool _dirty(String path) => _queue.any(
    (q) =>
        _resource(q['path'] as String) == _resource(path) ||
        q['creating'] == true && path.contains('/${q['local_id']}') ||
        Uri.parse(path).path.endsWith('/recipes') &&
            (q['path'] as String).startsWith('${Uri.parse(path).path}/'),
  );

  String? _recipeRoot(String path) {
    final parts = Uri.parse(path).pathSegments;
    return parts.length >= 3 && parts[2] == 'recipes'
        ? '/${parts.take(3).join('/')}'
        : null;
  }

  int _version(String path) =>
      (_versions[_resource(path)] ?? 0) + (_versions[_recipeRoot(path)] ?? 0);
  void _bump(String path) {
    final resource = _resource(path);
    _versions[resource] = (_versions[resource] ?? 0) + 1;
    final root = _recipeRoot(path);
    if (root != null && root != resource) {
      _versions[root] = (_versions[root] ?? 0) + 1;
    }
  }

  Future<Map<String, dynamic>?> cached(String input) async {
    await _load();
    final path = _path(input), uri = Uri.parse(_path(input));
    if (_blocked.keys.any((prefix) => _under(path, prefix))) return null;
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
      return _overlayRecipes(path, result);
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
        if (fallback == null) {
          return {
            'recipes': pairings
                .where((p) => p['in_household'] != false)
                .toList(),
          };
        }
        final owned = <String>{};
        int? offset = 0;
        do {
          final inventory = await fallback!.call(
            '/households/${parts[1]}/recipes?offset=$offset',
          );
          if (inventory == null) return null;
          owned.addAll(
            (inventory['recipes'] as List? ?? []).map((row) => '${row['id']}'),
          );
          offset = inventory['next_offset'] as int?;
        } while (offset != null);
        return {
          'recipes': pairings
              .where((p) => owned.contains('${p['id']}'))
              .toList(),
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
    if (parts.length == 3 &&
        parts[2] == 'recipes' &&
        uri.queryParameters.containsKey('favorite_people')) {
      final wanted = uri.queryParameters['favorite_people']!.split(',');
      final all = <dynamic>[];
      int? offset = 0;
      do {
        final query = {
          ...uri.queryParameters,
          'offset': '$offset',
          'tree': '0',
          'families': '0',
        }..remove('favorite_people');
        final page = await fallback?.call(
          Uri(path: uri.path, queryParameters: query).toString(),
        );
        if (page == null) return null;
        for (final row in page['recipes'] as List? ?? []) {
          final favorites = _data['${uri.path}/${row['id']}/favorites'] as Map?;
          if (favorites == null) return null;
          final people = favorites['people'] as List? ?? [];
          if (wanted.every(
            (id) => people.any(
              (person) => '${person['id']}' == id && person['favorite'] == true,
            ),
          )) {
            all.add(row);
          }
        }
        offset = page['next_offset'] as int?;
      } while (offset != null);
      final start = int.tryParse(uri.queryParameters['offset'] ?? '0') ?? 0;
      return {
        'recipes': all.skip(start).take(30).toList(),
        'view': 'recipes',
        'category_nodes': [],
        'next_offset': start + 30 < all.length ? start + 30 : null,
      };
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
    final saved = await fallback?.call(path);
    if (saved != null) {
      // Recipe inventory/detail synthesis is supplied by OfflineRecipes.
      return _overlayRecipes(path, saved);
    }
    if (parts.length == 3 &&
        parts[2] == 'recipes' &&
        _queue.any((q) => q['creating'] == true && q['path'] == uri.path)) {
      return _overlayRecipes(path, {
        'recipes': [],
        'category_nodes': [],
        'view': 'recipes',
        'next_offset': null,
      });
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

  Map<String, dynamic> _overlayRecipes(
    String path,
    Map<String, dynamic> saved,
  ) {
    final result = _copy(saved), uri = Uri.parse(path);
    if (uri.pathSegments.length != 3 || result['recipes'] is! List) {
      return result;
    }
    final rows = result['recipes'] as List;
    for (var i = 0; i < rows.length; i++) {
      final detail = _data['${uri.path}/${rows[i]['id']}'] as Map?;
      if (detail?['recipe'] is Map) {
        rows[i] = {...rows[i] as Map, ...detail!['recipe'] as Map};
      }
    }
    // Unsynchronized creations are part of the local inventory immediately.
    // Only include rows matching this view; never show another category's data.
    final localCreations =
        _queue
            .where((q) => q['creating'] == true && q['path'] == uri.path)
            .map((q) => '${q['local_id']}')
            .toSet()
          ..addAll(_aliases.values.map((id) => '$id'));
    for (final id in localCreations) {
      final recipe = (_data['${uri.path}/$id'] as Map?)?['recipe'] as Map?;
      if (recipe == null || rows.any((row) => row['id'] == recipe['id'])) {
        continue;
      }
      final scope = uri.queryParameters['scope'];
      final categories = recipe['category_assignments'] as List? ?? [];
      if (scope != null &&
          !categories.any(
            (c) =>
                '${c['category_id']}' == scope || '${c['parent_id']}' == scope,
          )) {
        continue;
      }
      if (uri.queryParameters.containsKey('favorite_people')) continue;
      final query = uri.queryParameters['q'] ?? '';
      if (!'${recipe['title']}'.toLowerCase().contains(query.toLowerCase())) {
        continue;
      }
      rows.add(_copy(recipe));
    }
    return result;
  }

  Future<String?> snapshotVersion(String household) async {
    await _load();
    return _data['snapshot-version:$household'] as String?;
  }

  Future<void> installSnapshot(Map<String, dynamic> snapshot) => _serial(
    () async {
      await _load();
      if (snapshot['schema'] != 1 ||
          snapshot['household_id'] is! String ||
          snapshot['version'] is! String ||
          snapshot['recipes'] is! List ||
          snapshot['categories'] is! List ||
          snapshot['responses'] is! Map ||
          snapshot['edit_options'] is! Map) {
        throw const FormatException('Incomplete household snapshot');
      }
      final household = snapshot['household_id'] as String;
      final accessEpoch = _accessEpoch;
      if (_blocked.keys.any(
        (prefix) => _under('/households/$household/', prefix),
      )) {
        throw ApiException(403, 'Household access was removed.');
      }
      final supplied = snapshot['responses'] as Map;
      for (final row in snapshot['recipes'] as List) {
        if (supplied['/households/$household/recipes/${row['id']}']?['recipe']
                is! Map ||
            supplied['/households/$household/recipes/${row['id']}/favorites']
                is! Map) {
          throw const FormatException('Incomplete recipe snapshot');
        }
      }
      for (final resource in ['people', 'shopping-list', 'recipe-blank']) {
        if (supplied['/households/$household/$resource'] is! Map) {
          throw const FormatException('Incomplete household resources');
        }
      }
      final prefix = '/households/$household/';
      final responses = Map<String, dynamic>.from(snapshot['responses'] as Map);
      final options = snapshot['edit_options'] as Map;
      final next = Map<String, dynamic>.from(_data);
      next.removeWhere(
        (path, _) =>
            path.startsWith(prefix) &&
            !_dirty(path) &&
            !_aliases.values.any((id) => path == '${prefix}recipes/$id'),
      );
      for (final entry in responses.entries) {
        if (!_dirty(entry.key)) {
          next[entry.key] = _copy(entry.value as Map);
        } else if (entry.key.endsWith('/shopping-list')) {
          final pending = _queue.where((q) => q['path'] == entry.key).toList();
          if (pending.every((q) => (q['body'] as Map)['base_items'] is List)) {
            next[entry.key] = overlayShoppingChanges(
              _copy(entry.value as Map),
              pending,
            );
          }
        }
      }
      next['snapshot-version:$household'] = snapshot['version'];
      next['snapshot-categories:$household'] = _copy({
        'rows': snapshot['categories'],
      })['rows'];
      next['snapshot-options:$household'] = _copy(options);
      await _persist(data: next);
      if (accessEpoch != _accessEpoch) {
        throw ApiException(
          403,
          'Household access changed during synchronization.',
        );
      }
      _data = next;
      _bump(prefix);
      for (final resource in [
        'recipes',
        'shopping-list',
        'restaurants',
        'meal-plan',
        'people',
      ]) {
        _changed('$prefix$resource');
      }
    },
  );

  /// Ready household screens read the committed in-memory generation directly.
  /// Never wait for file I/O, an outbox write, a token, or a background download.
  Map<String, dynamic> readView(String input) {
    final path = _path(input);
    if (_closed) throw StateError('Repository closed');
    if (_blocked.keys.any((prefix) => _under(path, prefix))) {
      throw ApiException(
        403,
        'Access to this data was removed.',
        code: 'household_access_removed',
      );
    }
    final uri = Uri.parse(path);
    final browse = _snapshotBrowse(uri);
    if (browse != null) return browse;
    final direct = _data[path];
    if (direct is Map) return _copy(direct);
    throw StateError('Local database is incomplete for $path');
  }

  Future<Map<String, dynamic>> request(String input) async {
    await _load();
    final path = _path(input);
    if (path != '/me' && _blocked.keys.any((prefix) => _under(path, prefix))) {
      throw ApiException(
        403,
        'Access to this data was removed. Reconnect and sign in again.',
        code: 'household_access_removed',
      );
    }
    if (!mirrors(path) || Uri.parse(path).path.endsWith('/recipes/deleted')) {
      return fetch(path);
    }
    if (snapshotOnly) {
      final saved = await cached(path);
      if (saved != null) return saved;
      throw StateError('Local database is incomplete for $path');
    }
    if (Uri.parse(path).pathSegments.any((part) => part.startsWith('local-'))) {
      final local = await cached(path);
      if (local != null) return local;
      throw ApiException(
        404,
        'This local recipe is not available on this device.',
      );
    }
    if (Uri.parse(path).path.endsWith('/meal-plan')) {
      final fullPath = '${Uri.parse(path).path}?from=2000-01-01&to=2199-12-31';
      _watch(fullPath);
      final local = await cached(path);
      if (local != null) {
        if (!_dirty(path)) {
          unawaited(refresh(fullPath).catchError((Object _) => local));
        }
        return local;
      }
      final full = await refresh(fullPath, force: true);
      return _filterPlan(full, Uri.parse(path));
    }
    _watch(path);
    final saved = await cached(path);
    if (saved != null) {
      if (!_dirty(path)) {
        unawaited(refresh(path).catchError((Object _) => saved));
      }
      return saved;
    }
    return refresh(path, force: true);
  }

  Future<Map<String, dynamic>> refresh(
    String input, {
    bool force = false,
  }) async {
    await _load();
    final path = _path(input);
    if (_closed) throw StateError('Repository closed');
    if (_dirty(path)) {
      final saved = await cached(path);
      if (saved != null) return saved;
    }
    if (_inflight.containsKey(path)) return _inflight[path]!;
    final previous = _attempted[path];
    final interval = Uri.parse(path).path.endsWith('/shopping-list')
        ? const Duration(seconds: 5)
        : const Duration(seconds: 20);
    if (!force &&
        previous != null &&
        DateTime.now().difference(previous) < interval) {
      final saved = await cached(path);
      if (saved != null) return saved;
    }
    _attempted[path] = DateTime.now();
    if (_attempted.length > 64) _attempted.remove(_attempted.keys.first);
    final accessEpoch = _accessEpoch;
    final version = _version(path);
    final task = () async {
      try {
        final result = await fetch(path);
        if (accessEpoch != _accessEpoch) {
          throw ApiException(
            403,
            'Household access changed. Reconnect before loading this data.',
            code: 'household_access_removed',
          );
        }
        if (version != _version(path)) {
          final latest = await cached(path);
          if (latest != null) return latest;
          throw ApiException(
            404,
            'This data changed while synchronizing. Open it again.',
          );
        }
        if (_closed || _dirty(path)) return await cached(path) ?? result;
        if (path == '/me') _prune(result);
        final changed = jsonEncode(_data[path]) != jsonEncode(result);
        _data[path] = _copy(result);
        error = null;
        // A complete plan snapshot serves all calendar ranges locally.
        if (Uri.parse(path).path.endsWith('/meal-plan') &&
            Uri.parse(path).queryParameters['from'] == '2000-01-01' &&
            Uri.parse(path).queryParameters['to'] == '2199-12-31') {
          _data[Uri.parse(path).path] = _copy(result);
        }
        unawaited(
          _persist().catchError((Object _) {
            error = 'Device storage could not be saved. Free space and retry.';
            _changed(path);
          }),
        );
        if (changed) _changed(path);
        return result;
      } catch (failure) {
        if (failure is ApiException && _denyFailure(path, failure)) {
          await _persist();
          _changed(path);
        } else {
          error = 'Sync paused. Showing local data; saved edits remain on this device.';
          if (!_closed) notifyListeners();
        }
        rethrow;
      } finally {
        _inflight.remove(path);
      }
    }();
    _inflight[path] = task;
    return task;
  }

  void _prune(Map result) {
    final rows = result['households'];
    if (rows is! List ||
        rows.any(
          (row) =>
              row is! Map || !RegExp(r'^[1-9][0-9]*$').hasMatch('${row['id']}'),
        )) {
      throw const FormatException('Invalid household membership response');
    }
    final households = rows.map((h) => '${h['id']}').toSet();
    final accountBlocked = _blocked.remove('/') != null;
    final meBlocked = _blocked.remove('/me') != null;
    for (final household in households) {
      final restored = _blocked.remove('/households/$household/') != null;
      final rootRestored = _blocked.remove('/households/$household') != null;
      if (accountBlocked || meBlocked || restored || rootRestored) {
        // An old false denial may have removed records but kept the version.
        // Force a complete download instead of accepting an unchanged receipt.
        _data.remove('snapshot-version:$household');
      }
    }
    for (final q in _queue) {
      final parts = Uri.parse(q['path'] as String).pathSegments;
      if (parts.length >= 2 &&
          households.contains(parts[1]) &&
          [
            'invalid_token',
            'authentication_required',
          ].contains(q['problem_code'])) {
        q.remove('problem');
        q.remove('problem_code');
      }
    }
    final removed = _data.keys
        .where(
          (p) =>
              p.startsWith('/households/') &&
              !households.contains(Uri.parse(p).pathSegments[1]),
        )
        .toList();
    for (final path in removed) {
      _deny(path);
    }
  }

  bool _denyFailure(String path, ApiException failure) {
    // A denied action, expired token or proxy error is not membership removal.
    // Only authoritative API codes may revoke the corresponding local scope.
    if ([401, 403].contains(failure.status) &&
        ['account_disabled', 'account_deleted'].contains(failure.code)) {
      return _deny('/me', failure.status);
    }
    final parts = Uri.parse(path).pathSegments;
    if (failure.status == 404 &&
        failure.code == 'household_not_found' &&
        parts.length >= 2 &&
        parts[0] == 'households') {
      return _deny('/households/${parts[1]}/');
    }
    if (failure.status == 404 && failure.code == 'recipe_not_found') {
      return _deny(path, 404);
    }
    return false;
  }

  bool _deny(String path, [int status = 403]) {
    final parts = Uri.parse(path).pathSegments;
    final prefix = path == '/me' || status == 401
        ? '/'
        : status == 404
        ? Uri.parse(path).path
        : parts.length >= 2
        ? '/households/${parts[1]}/'
        : path;
    final newlyBlocked = !_blocked.containsKey(prefix);
    if (newlyBlocked) _accessEpoch++;
    _blocked[prefix] = status;
    _data.removeWhere((p, _) => _under(p, prefix));
    if (parts.length >= 2 && prefix == '/households/${parts[1]}/') {
      for (final kind in ['version', 'categories', 'options']) {
        _data.remove('snapshot-$kind:${parts[1]}');
      }
    }
    for (final q in _queue.where((q) => _under(q['path'] as String, prefix))) {
      _archive.add({
        ...q,
        'problem': 'Access removed. Local draft retained for recovery.',
      });
    }
    _queue.removeWhere((q) => _under(q['path'] as String, prefix));
    return newlyBlocked;
  }

  bool canSave(String path) => RegExp(
    r'^/households/[^/]+/(shopping-list|restaurants|meal-plan|recipes(?:/(?:[1-9][0-9]*|local-[a-zA-Z0-9_-]+)(?:/favorites)?)?)$',
  ).hasMatch(path);

  Future<Map<String, dynamic>> save(String input, Map<String, dynamic> body) {
    requireChildModeWrite(input);
    return _serial(() => _save(input, body));
  }

  Future<Map<String, dynamic>> _save(
    String input,
    Map<String, dynamic> body,
  ) async {
    await _load();
    final path = _path(input);
    if (_blocked.keys.any((prefix) => _under(path, prefix))) {
      throw ApiException(
        403,
        'Access to this data was removed. Local drafts are retained.',
      );
    }
    if (Uri.parse(path).path.endsWith('/meal-plan') &&
        ['add', 'move'].contains(body['operation'])) {
      final date = body['date'];
      final parsed = date is String ? DateTime.tryParse(date) : null;
      if (date is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.year < 2000 ||
          parsed.year > 2199 ||
          !parsed.toIso8601String().startsWith('${date}T')) {
        throw ApiException(
          422,
          'Choose a date for this meal.',
          code: 'date_required',
        );
      }
    }
    if (!canSave(path)) return send(path, body);
    final before = jsonEncode({'data': _data, 'queue': _queue});
    final resource = Uri.parse(path).path;
    final value = _copy(body);
    final previous = await cached(resource);
    final previousRevision =
        (previous?['recipe'] as Map?)?['revision'] ?? previous?['revision'];
    if (body['revision'] != null &&
        previousRevision != null &&
        '${body['revision']}' != '$previousRevision') {
      throw ApiException(
        409,
        'This data changed on this device. Review the current version and try again.',
      );
    }
    final id = newShoppingItemId();
    final q = <String, dynamic>{
      'id': id,
      'path': resource,
      'body': value,
      'saved_at': now().millisecondsSinceEpoch,
    };
    if (resource.contains('/recipes') && !resource.endsWith('/favorites')) {
      value['client_save_id'] = id;
    }
    Map<String, dynamic> response;
    if (path.endsWith('/favorites')) {
      final old = await cached(path);
      if (old == null) {
        throw ApiException(
          503,
          'Download favorites once before editing them offline.',
        );
      }
      response = _copy(old);
      final person = body['person_id'] ?? old['current_person_id'];
      final people = response['people'] as List? ?? [];
      for (final row in people) {
        if (row['id'] == person) row['favorite'] = body['favorite'];
      }
    } else if (path.endsWith('/restaurants')) {
      final old = await cached(path);
      if (old == null) {
        throw ApiException(503, 'Download the restaurant list before editing.');
      }
      response = {
        ...old,
        'revision': body['revision'] + 1,
        'items': value['items'],
      };
    } else if (path.endsWith('/shopping-list')) {
      final old = await cached(path);
      if (old == null) {
        throw ApiException(
          503,
          'Download this list once before editing offline.',
        );
      }
      final editedAt = now().millisecondsSinceEpoch + (_serverOffsetMs ?? 0);
      _lastShoppingEditMs = editedAt > _lastShoppingEditMs
          ? editedAt
          : _lastShoppingEditMs + 1;
      value['client_change_id'] = id;
      value['edited_at_ms'] = _lastShoppingEditMs;
      value['base_items'] = _copy({'items': old['items']})['items'];
      response = {
        ...old,
        'revision': body['revision'] + 1,
        'items': value['items'],
      };
    } else if (path.endsWith('/meal-plan')) {
      final old = await cached(path);
      if (old == null) {
        throw ApiException(
          503,
          'Download the meal plan once before editing offline.',
        );
      }
      response = _copy(old);
      final entries = response['entries'] as List;
      final operation = value['operation'], entryId = value['id'];
      final existing = entries.where((e) => e['id'] == entryId).firstOrNull;
      if (operation == 'add') {
        final recipe =
            (await cached(
                  '${path.replaceFirst('/meal-plan', '/recipes')}/${value['recipe_id']}',
                ))?['recipe']
                as Map?;
        if (value['kind'] == 'recipe' && recipe == null) {
          throw ApiException(
            503,
            'Download this recipe before adding it to the local meal plan.',
          );
        }
        Map? restaurant;
        if (value['kind'] == 'restaurant' && value['restaurant_id'] != null) {
          final list = await cached(
            path.replaceFirst('/meal-plan', '/restaurants'),
          );
          for (final item in (list?['items'] as List? ?? [])) {
            if (item['id'] == value['restaurant_id']) restaurant = item as Map;
          }
          if (restaurant == null) {
            throw ApiException(
              422,
              'Choose an available household restaurant.',
            );
          }
        }
        entries.add({
          'photo_url': recipe == null ? null : localRecipeCover(recipe),
          'restaurant_id': restaurant?['id'],
          'restaurant_logo_reference': restaurant?['logo_reference'],
          'id': entryId,
          'kind': value['kind'],
          'plan_date': value['date'],
          'recipe_id': value['recipe_id'],
          'recipe_identity': value['recipe_id'],
          'title':
              recipe?['title'] ??
              (value['kind'] == 'leftovers'
                  ? 'Leftovers'
                  : restaurant?['name'] ?? 'Restaurant'),
          'available': recipe != null,
          'recipe_revision': recipe?['revision'],
        });
      } else if (operation == 'move' && existing != null) {
        existing['plan_date'] = value['date'];
      } else if (operation == 'remove') {
        entries.removeWhere((e) => e['id'] == entryId);
      } else {
        throw ApiException(409, 'This meal is no longer available locally.');
      }
      response['revision'] = body['revision'] + 1;
    } else {
      final creating = Uri.parse(path).pathSegments.length == 3;
      final localId = creating
          ? 'local-$id'
          : Uri.parse(path).pathSegments.last;
      q['local_id'] = localId;
      q['creating'] = creating;
      final old = creating ? null : (await cached(path))?['recipe'] as Map?;
      final recipe = {
        ...?old,
        ...value,
        'id': localId,
        'revision': '${(int.tryParse('${body['revision']}') ?? 0) + 1}',
      };
      response = {'recipe': recipe};
      _data['${creating ? path : path.substring(0, path.lastIndexOf('/'))}/$localId'] =
          response;
    }
    final creating = q['creating'] == true;
    if (!creating) _data[resource] = _copy(response);
    // Browse snapshots must be rebuilt from the inventory after a recipe edit.
    if (resource.contains('/recipes/')) {
      final root = resource.substring(0, resource.indexOf('/recipes/') + 8);
      _data.removeWhere((p, _) => Uri.parse(p).path == root);
    }
    _data.removeWhere((p, _) => Uri.parse(p).path == resource && p != resource);
    _queue.add(q);
    try {
      await _persist();
    } catch (_) {
      final restore = jsonDecode(before) as Map;
      _data = Map<String, dynamic>.from(restore['data'] as Map);
      _queue = (restore['queue'] as List).map((q) => _copy(q as Map)).toList();
      throw ApiException(
        507,
        'Could not save on this device. Your change has not been queued. Free storage and retry.',
      );
    }
    _bump(resource);
    _changed(resource);
    // Start after this local transaction releases its serialization lock.
    scheduleMicrotask(() => unawaited(synchronize()));
    return _copy(response);
  }

  Future<void> synchronize() =>
      _draining ??= _drain().whenComplete(() => _draining = null);

  Future<void> _drain() async {
    await _load();
    while (!_closed && _queue.isNotEmpty) {
      if (online?.call() == false) return;
      // Preserve order within a resource; a conflict in one household must not
      // prevent independent households/resources from synchronizing.
      final q = _queue.where((candidate) {
        if (candidate['problem'] != null) return false;
        final earlier = _queue.takeWhile((q) => q != candidate);
        if (earlier.any(
          (q) =>
              _resource(q['path'] as String) ==
              _resource(candidate['path'] as String),
        )) {
          return false;
        }
        final body = candidate['body'] as Map;
        return !Uri.parse(_path(candidate['path'] as String)).pathSegments.last
                .startsWith('local-') &&
            ![
              'recipe_id',
              'parent_recipe_id',
            ].any((field) => '${body[field]}'.startsWith('local-'));
      }).firstOrNull;
      if (q == null) return;
      final path = _path(q['path'] as String);
      var delivered = false;
      final accessEpoch = _accessEpoch;
      try {
        await _serial(() async {
          q['sending'] = true;
          await _persist(); // Crash during send is never mistaken for unsent work.
        });
        final received = await send(path, _copy(q['body'] as Map));
        if (path.endsWith('/shopping-list') &&
            (q['body'] as Map)['client_change_id'] != null &&
            received['acknowledged_change_id'] !=
                (q['body'] as Map)['client_change_id']) {
          throw ApiException(
            503,
            'The shopping change was not acknowledged. It remains saved on this device.',
          );
        }
        final result = Map<String, dynamic>.from(received)
          ..remove('acknowledged_change_id');
        delivered = true;
        if (_closed || accessEpoch != _accessEpoch) return;
        await _serial(() async {
          if (q['creating'] == true) {
            final serverId = '${(result['recipe'] as Map)['id']}';
            final localId = q['local_id'] as String;
            _aliases[localId] = serverId;
            final root = Uri.parse(path).path;
            final newerLocal = _data['$root/$localId'] as Map?;
            _data.remove('$root/$localId');
            // Resolve references in queued plan/recipe changes, not arbitrary text.
            for (final pending in _queue.skip(1)) {
              final b = pending['body'] as Map;
              for (final field in ['recipe_id', 'parent_recipe_id']) {
                if (b[field] == localId) b[field] = serverId;
              }
              pending['path'] = _path(pending['path'] as String);
            }
            if (newerLocal != null &&
                _queue
                    .skip(1)
                    .any((pending) => pending['path'] == '$root/$serverId')) {
              final local = _copy(newerLocal);
              (local['recipe'] as Map)['id'] = serverId;
              _data['$root/$serverId'] = local;
            } else {
              _data['$root/$serverId'] = _copy(result);
            }
          }
          _queue.remove(q);
          final next = _queue
              .where(
                (p) =>
                    _path(p['path'] as String) ==
                    (q['creating'] == true
                        ? '$path/${_aliases[q['local_id']]}'
                        : path),
              )
              .firstOrNull;
          if (next != null && result['recipe'] is Map) {
            final recipe = result['recipe'] as Map;
            final body = next['body'] as Map;
            body['revision'] = recipe['revision'];
            // The server assigns child-row IDs. Carry those into a later local
            // edit without replacing its content with an older server response.
            final sent = q['body'] as Map;
            final ids = <String, Map<String, String>>{};
            for (final field in [
              'ingredients',
              'groups',
              'steps',
              'actions',
              'photos',
            ]) {
              ids[field] = {};
              final old = sent[field] as List? ?? [],
                  saved = recipe[field] as List? ?? [];
              for (var i = 0; i < old.length && i < saved.length; i++) {
                if (old[i]['id'] != null && saved[i]['id'] != null) {
                  ids[field]!['${old[i]['id']}'] = '${saved[i]['id']}';
                }
              }
            }
            _remapChildren(body, ids);
          }
          if (!_dirty(path)) {
            if (result['recipe'] is Map) {
              if (q['creating'] != true) {
                _data[path] = _copy(result);
              }
            } else if (path.endsWith('/shopping-list') ||
                path.endsWith('/restaurants') ||
                path.endsWith('/favorites')) {
              _data[path] = _copy(result);
            } else if (path.endsWith('/meal-plan')) {
              (_data[path] as Map?)?['revision'] = result['revision'];
            }
          }
          error = null;
          await _persist();
          _bump(path);
          _changed(path);
        });
        if (result['recipe'] is Map) {
          final recipePath = q['creating'] == true
              ? '$path/${(result['recipe'] as Map)['id']}'
              : path;
          try {
            await onRecipeSaved?.call(recipePath, result);
          } catch (_) {
            error = 'The server saved this recipe, but its local search index needs another sync.';
            _changed(recipePath);
          }
        }
      } catch (failure) {
        await _serial(() async {
          q.remove('sending');
          if (delivered && !_queue.contains(q)) _queue.insert(0, q);
          if (failure is ApiException && _denyFailure(path, failure)) {
            _changed(path);
          }
          // Receipt-backed recipe saves can replay after lost responses/crashes.
          // Legacy creates without a receipt identifier still require review.
          q['last_attempt_at'] = now().millisecondsSinceEpoch;
          q['attempts'] = (q['attempts'] as int? ?? 0) + 1;
          q['last_error'] = failure is ApiException
              ? failure.message
              : 'The server response was interrupted.';
          q['last_status'] = failure is ApiException ? failure.status : null;
          if ((delivered && (q['body'] as Map)['client_change_id'] == null) ||
              q['creating'] == true &&
                  (q['body'] as Map)['client_save_id'] == null ||
              failure is ApiException &&
                  !isTemporaryCommunicationFailure(failure)) {
            q['problem'] = failure is ApiException ? failure.message : 'The save response was lost. Review the server before retrying this new recipe.';
            if (failure is ApiException) q['problem_code'] = failure.code;
            if (delivered) q['problem'] = 'The server accepted this change, but this device could not record the confirmation. Compare with the server before continuing.';
          }
          error =
              'Synchronization paused; $pending local change(s) are saved on this device.';
          try {
            await _persist();
          } catch (_) {
            error = 'Device storage is unavailable. Synchronization paused; do not clear app data.';
          }
          if (!_closed) notifyListeners();
        });
        if (q['problem'] == null) break;
      }
    }
  }

  /// Resolve by keeping the server version. Preserve the local draft in an
  /// archive, rather than discarding it, and never force an old revision.
  Future<void> keepServer(String id) async {
    await _load();
    final q = _queue.firstWhere((q) => q['id'] == id);
    final path = _path(q['path'] as String);
    final serverPath = path.endsWith('/meal-plan')
        ? '$path?from=2000-01-01&to=2199-12-31'
        : path;
    final server = await (readServer ?? fetch)(serverPath);
    await _serial(() async {
      final related = _queue
          .where(
            (p) => q['creating'] == true
                ? p['id'] == q['id'] ||
                      (p['path'] as String).endsWith('/${q['local_id']}') ||
                      (p['body'] as Map)['recipe_id'] == q['local_id']
                : p['path'] == q['path'],
          )
          .toList();
      _archive.addAll(related.map(_copy));
      _queue.removeWhere((p) => related.contains(p));
      _data[path] = _copy(server);
      if (q['creating'] == true) _data.remove('$path/${q['local_id']}');
      error = null;
      await _persist();
      _bump(path);
      _changed(path);
    });
    unawaited(synchronize());
  }

  /// Explicit conflict resolution against the version the user has just seen.
  /// A further server edit still produces a conflict, never a force overwrite.
  Future<void> useLocal(String id, Map<String, dynamic> server) async {
    await _serial(() async {
      final first = _queue.firstWhere((q) => q['id'] == id);
      if (first['creating'] == true) {
        throw ApiException(
          409,
          'Check whether this recipe was already saved before creating another copy.',
        );
      }
      final related = _queue.where((q) => q['path'] == first['path']).toList();
      final latest = related.last;
      final body = _copy(latest['body'] as Map);
      if (first['problem_code'] == 'past_confirmation_required') {
        body['confirm_past'] = true;
      }
      if (first['problem_code'] == 'shared_confirmation_required') {
        body['confirm_shared_edit'] = true;
      }
      body['revision'] =
          (server['recipe'] as Map?)?['revision'] ?? server['revision'];
      if ((first['path'] as String).endsWith('/shopping-list')) {
        if (related.every((q) => (q['body'] as Map)['base_items'] is List)) {
          body['items'] = overlayShoppingChanges(server, related)['items'];
        }
        body['base_items'] = _copy({'items': server['items']})['items'];
        body['client_change_id'] = newShoppingItemId();
        final editedAt = now().millisecondsSinceEpoch + (_serverOffsetMs ?? 0);
        _lastShoppingEditMs = editedAt > _lastShoppingEditMs
            ? editedAt
            : _lastShoppingEditMs + 1;
        body['edited_at_ms'] = _lastShoppingEditMs;
      }
      if (server['recipe'] is Map) {
        final ids = <String, Map<String, String>>{};
        var next = 0;
        for (final field in [
          'ingredients',
          'groups',
          'steps',
          'actions',
          'photos',
        ]) {
          ids[field] = {};
          for (final row in body[field] as List? ?? []) {
            if (row['id'] != null) {
              ids[field]!['${row['id']}'] = 'new-local-${next++}';
            }
          }
        }
        _remapChildren(body, ids);
      } else if ((first['path'] as String).endsWith('/meal-plan') &&
          related.length > 1) {
        // Calendar operations are ordered deltas, not replaceable snapshots.
        // Rebase only the first operation; later operations retain their order.
        body.clear();
        body.addAll(_copy(first['body'] as Map));
        if (first['problem_code'] == 'past_confirmation_required') {
          body['confirm_past'] = true;
        }
        body['revision'] = server['revision'];
      }
      _archive.addAll(related.map(_copy));
      if ((first['path'] as String).endsWith('/meal-plan')) {
        first['body'] = body;
        first.remove('problem');
        first.remove('sending');
        var revision = (server['revision'] as num).toInt();
        for (final q in related) {
          (q['body'] as Map)['revision'] = revision++;
        }
      } else {
        _queue.removeWhere((q) => related.contains(q));
        final saveId = newShoppingItemId();
        if (body.containsKey('client_save_id')) body['client_save_id'] = saveId;
        _queue.insert(0, {
          'id': saveId,
          'path': first['path'],
          'body': body,
          'saved_at': now().millisecondsSinceEpoch,
        });
      }
      await _persist();
      _changed(first['path'] as String);
    });
    await synchronize();
  }

  Future<Map<String, dynamic>> serverCopy(Map<String, dynamic> q) =>
      (readServer ?? fetch)(
        (q['path'] as String).endsWith('/meal-plan')
            ? '${q['path']}?from=2000-01-01&to=2199-12-31'
            : q['path'] as String,
      );

  void start() {
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      unawaited(synchronize().catchError((Object _) {}));
      if (snapshotOnly) return;
      for (final path in _watched.values.toList()) {
        if (!_dirty(path)) {
          unawaited(
            refresh(path).catchError((Object _) => <String, dynamic>{}),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _reminderTimer?.cancel();
    super.dispose();
  }
}

class LocalSyncStatus extends StatelessWidget {
  const LocalSyncStatus({super.key, required this.data});
  final LocalData data;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data,
    builder: (context, _) => data.pending == 0 && data.error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (data.overdue > 0
                            ? '${data.overdue} change(s) still await server confirmation after one minute. Saved on this device.${data.lastSyncFailure == null ? '' : ' ${data.lastSyncFailure}'}'
                            : null) ??
                        data.reminderError ??
                        data.error ??
                        '${data.pending} change(s) saved on this device · awaiting server confirmation',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (data.conflicts.isEmpty) {
                      await data.synchronize();
                      return;
                    }
                    final q = data.conflicts.first;
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: const Text('Review local change'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            '${q['problem']}\n\nLocal edit (retained on this device):\n${describeLocalData(q['body'] as Map)}',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: const Text('Keep local draft'),
                          ),
                          TextButton(
                            onPressed: () async {
                              try {
                                final server = await data.serverCopy(q);
                                if (!dialog.mounted) return;
                                final accept = await showDialog<String>(
                                  context: dialog,
                                  builder: (review) => AlertDialog(
                                    title: const Text('Server version'),
                                    content: SingleChildScrollView(
                                      child: SelectableText(
                                        describeLocalData(server),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(review, 'cancel'),
                                        child: const Text('Cancel'),
                                      ),
                                      if (q['creating'] != true)
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(review, 'local'),
                                          child: const Text(
                                            'Apply my local changes',
                                          ),
                                        ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(review, 'server'),
                                        child: const Text(
                                          'Use server; archive local draft',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (accept == 'local') {
                                  await data.useLocal(
                                    q['id'] as String,
                                    server,
                                  );
                                }
                                if (accept == 'server') {
                                  await data.keepServer(q['id'] as String);
                                }
                                if (dialog.mounted &&
                                    accept != null &&
                                    accept != 'cancel') {
                                  Navigator.pop(dialog);
                                }
                              } catch (_) {
                                if (dialog.mounted) {
                                  ScaffoldMessenger.of(dialog).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not load the server version. Local edits are retained.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('Compare with server'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(data.conflicts.isEmpty ? 'Sync now' : 'Review'),
                ),
              ],
            ),
          ),
  );
}
