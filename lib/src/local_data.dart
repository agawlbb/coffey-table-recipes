import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_store.dart';
import 'shopping_item_id.dart';

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
    lines.add('${data['operation']} meal · ${data['date'] ?? 'Unscheduled'}');
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
      '${row['plan_date'] ?? 'Unscheduled'} · ${row['title'] ?? row['kind']}',
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
    this.readStore = readOfflineStore,
    this.writeStore = writeOfflineStore,
  });

  final String key;
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
  Timer? _timer;
  bool _closed = false;
  int _epoch = 0;
  int _accessEpoch = 0;
  String? error;
  int get pending => _queue.length;
  List<Map<String, dynamic>> get conflicts =>
      _queue.where((q) => q['problem'] != null).map(_copy).toList();
  List<Map<String, dynamic>> get archivedDrafts => _archive.map(_copy).toList();

  Future<Map<String, dynamic>?> cachedView(String path) async {
    _watch(path);
    final saved = await cached(path);
    if (saved != null && !_dirty(path)) {
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
      _queue = (saved['queue'] as List).map((q) => _copy(q as Map)).toList();
      _archive = (saved['archive'] as List? ?? [])
          .map((q) => _copy(q as Map))
          .toList();
      for (final q in _queue) {
        if (q['sending'] == true) {
          q['problem'] = 'The app closed during synchronization. Review the server copy before retrying.';
        }
      }
    } catch (_) {
      // Preserve the damaged source instead of silently overwriting edits.
      throw const FormatException(
        'Local data could not be read. Restore device storage before continuing.',
      );
    }
  }();

  Future<void> _persist() {
    final value = jsonEncode({
      'data': _data,
      'queue': _queue,
      'archive': _archive,
      'aliases': _aliases,
      'blocked': _blocked,
    });
    final task = _disk.then((_) => writeStore('local-first-v1-$key', value));
    _disk = task.catchError((Object _) {});
    return task;
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
        r'^/households/[^/]+/(recipes|people|shopping-list|meal-plan)(/[^?]+)?(\?.*)?$',
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
    final direct = _data[path];
    if (direct is Map &&
        !uri.path.contains('/meal-plan/ingredients') &&
        !uri.path.contains('/meal-plan/pairings/')) {
      return _overlayRecipes(path, _copy(direct));
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
          for (final ingredient in recipe['ingredients'] as List? ?? []) {
            rows.add({
              ...Map<String, dynamic>.from(ingredient as Map),
              'meal_entry_id': meal['id'],
              'plan_date': meal['plan_date'],
              'recipe_title': recipe['title'],
            });
          }
        }
        return {'ingredients': rows};
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

  Map<String, dynamic> _filterPlan(Map state, Uri uri) {
    final result = _copy(state);
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
    if (!mirrors(path)) return fetch(path);
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
        final changed = jsonEncode(_data[path]) != jsonEncode(result);
        _data[path] = _copy(result);
        error = null;
        // A complete plan snapshot serves all calendar ranges locally.
        if (Uri.parse(path).path.endsWith('/meal-plan') &&
            Uri.parse(path).queryParameters['from'] == '2000-01-01' &&
            Uri.parse(path).queryParameters['to'] == '2199-12-31') {
          _data[Uri.parse(path).path] = _copy(result);
        }
        if (path == '/me') _prune(result);
        unawaited(
          _persist().catchError((Object _) {
            error = 'Device storage could not be saved. Free space and retry.';
            _changed(path);
          }),
        );
        if (changed) _changed(path);
        return result;
      } catch (failure) {
        if (failure is ApiException &&
            [401, 403, 404].contains(failure.status)) {
          final newlyBlocked = _deny(path, failure.status);
          await _persist();
          if (newlyBlocked) _changed(path);
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
    final households = (result['households'] as List? ?? [])
        .map((h) => '${h['id']}')
        .toSet();
    _blocked.remove('/');
    _blocked.remove('/me');
    for (final household in households) {
      _blocked.remove('/households/$household/');
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
    r'^/households/[^/]+/(shopping-list|meal-plan|recipes(?:/(?:[1-9][0-9]*|local-[a-zA-Z0-9_-]+)(?:/favorites)?)?)$',
  ).hasMatch(path);

  Future<Map<String, dynamic>> save(String input, Map<String, dynamic> body) {
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
    final q = <String, dynamic>{'id': id, 'path': resource, 'body': value};
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
    } else if (path.endsWith('/shopping-list')) {
      final old = await cached(path);
      if (old == null) {
        throw ApiException(
          503,
          'Download this list once before editing offline.',
        );
      }
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
        entries.add({
          'id': entryId,
          'kind': value['kind'],
          'plan_date': value['date'],
          'recipe_id': value['recipe_id'],
          'recipe_identity': value['recipe_id'],
          'title':
              recipe?['title'] ??
              (value['kind'] == 'leftovers'
                  ? 'Leftovers'
                  : 'Restaurant outing'),
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
        final result = await send(path, _copy(q['body'] as Map));
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
          if (failure is ApiException && [401, 403].contains(failure.status)) {
            _deny(path, failure.status);
            _changed(path);
          }
          // Revision-checked writes can be retried safely; creates cannot, because
          // a lost success response could otherwise create a duplicate recipe.
          if (delivered ||
              q['creating'] == true ||
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
        _queue.insert(0, {
          'id': newShoppingItemId(),
          'path': first['path'],
          'body': body,
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
    super.dispose();
  }
}

class LocalSyncStatus extends StatelessWidget {
  const LocalSyncStatus({super.key, required this.data});
  final LocalData data;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data,
    builder: (context, _) =>
        data.pending == 0 && data.error == null && data.archivedDrafts.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    data.error ??
                        (data.pending == 0
                            ? 'Local drafts retained'
                            : '${data.pending} change(s) saved locally · syncing'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (data.archivedDrafts.isNotEmpty)
                  IconButton(
                    tooltip: 'Saved local drafts',
                    icon: const Icon(Icons.history),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: const Text('Saved local drafts'),
                        content: SizedBox(
                          width: 500,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              data.archivedDrafts
                                  .map(
                                    (draft) =>
                                        describeLocalData(draft['body'] as Map),
                                  )
                                  .join('\n\n────────\n\n'),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
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
