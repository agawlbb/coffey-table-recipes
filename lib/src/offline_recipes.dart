import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'api.dart';
import 'offline_store.dart';

final offlineStatus = ValueNotifier<bool>(false);
bool get mobileOfflineEnabled =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

typedef OfflineRequest = Future<Map<String, dynamic>> Function(String path);

class RecipeSyncProgress {
  const RecipeSyncProgress({
    this.saved = 0,
    this.total,
    this.working = false,
    this.ready = false,
    this.error,
  });
  final int saved;
  final int? total;
  final bool working;
  final bool ready;
  final String? error;
}

class OfflineStorageException implements Exception {}

/// Account and server scoped text storage. Only read endpoints are cached.
class OfflineRecipes with WidgetsBindingObserver {
  OfflineRecipes({
    required this.key,
    required this.fetch,
    this.read = readOfflineStore,
    this.write = writeOfflineStore,
  });
  final String key;
  final OfflineRequest fetch;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  Map<String, dynamic> _responses = {};
  Map<String, dynamic> _libraries = {};
  Map<String, dynamic> _pending = {};
  final progress = ValueNotifier<RecipeSyncProgress>(
    const RecipeSyncProgress(),
  );
  List<String> _syncHouseholds = [];
  Future<void>? _ready;
  Future<void> _writes = Future.value();
  Future<void>? _sync;
  bool _closed = false;
  int _accessVersion = 0;
  Set<String>? _knownHouseholds;
  StreamSubscription<List<ConnectivityResult>>? _connection;
  Timer? _retry;
  bool _probing = false;
  VoidCallback? _reconnect;

  Future<void> _probe() async {
    if (_closed || _probing) return;
    _probing = true;
    try {
      final results = await Connectivity().checkConnectivity();
      if (_closed) return;
      if (results.contains(ConnectivityResult.none)) {
        offlineStatus.value = true;
        return;
      }
      final me = await fetch('/me');
      if (_closed) return;
      await _load();
      _responses['/me'] = me;
      _pruneHouseholds(
        (me['households'] as List? ?? [])
            .map((h) => h['id'] as String)
            .toList(),
      );
      await _save();
      offlineStatus.value = false;
      _reconnect?.call();
    } catch (error) {
      if (!_closed && error is ApiException) {
        offlineStatus.value = false;
        await _invalidate('/me', error.status);
        _reconnect?.call();
      }
      if (!_closed && isOfflineFailure(error)) offlineStatus.value = true;
    } finally {
      _probing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_probe());
  }

  void start(VoidCallback reconnect) {
    _reconnect = reconnect;
    WidgetsBinding.instance.addObserver(this);
    offlineStatus.value = false;
    _connection = Connectivity().onConnectivityChanged.listen((results) {
      final disconnected = results.contains(ConnectivityResult.none);
      if (disconnected) {
        offlineStatus.value = true;
      } else if (offlineStatus.value && !_closed) {
        unawaited(_probe());
      }
    });
    _retry = Timer.periodic(const Duration(seconds: 30), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        if (offlineStatus.value) {
          unawaited(_probe());
        } else if (_knownHouseholds != null && !progress.value.ready) {
          unawaited(sync(_knownHouseholds!.toList()));
        }
      }
    });
    Connectivity()
        .checkConnectivity()
        .then((results) {
          if (!_closed && results.contains(ConnectivityResult.none)) {
            offlineStatus.value = results.contains(ConnectivityResult.none);
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _load() => _ready ??= () async {
    try {
      final source = await read(key);
      if (source != null) {
        final data = jsonDecode(source) as Map<String, dynamic>;
        _responses = Map<String, dynamic>.from(data['responses'] as Map);
        _libraries = Map<String, dynamic>.from(data['libraries'] as Map);
        _pending = Map<String, dynamic>.from(data['pending'] as Map? ?? {});
        final households = (_responses['/me'] as Map?)?['households'] as List?;
        if (households != null) {
          _knownHouseholds = households.map((h) => h['id'] as String).toSet();
          _syncHouseholds = _knownHouseholds!.toList();
          _updateProgress();
        }
      }
    } catch (_) {
      /* A missing/corrupt cache must not prevent online use. */
    }
  }();

  Future<void> _save({bool required = false}) async {
    final source = jsonEncode({
      'responses': _responses,
      'libraries': _libraries,
      'pending': _pending,
    });
    final operation = _writes.then((_) => write(key, source));
    _writes = operation.catchError((Object _) {});
    try {
      await operation;
    } catch (_) {
      _updateProgress(
        error:
            'Could not save recipes on this device. Free up storage and retry.',
      );
      if (required) throw OfflineStorageException();
    }
  }

  void _updateProgress({bool working = false, String? error}) {
    if (_closed) return;
    var saved = 0;
    var total = 0;
    var known = _syncHouseholds.isNotEmpty;
    var complete = known;
    for (final household in _syncHouseholds) {
      final pending = _pending[household] as Map?;
      final library = pending ?? _libraries[household] as Map?;
      if (library == null) {
        known = false;
        complete = false;
        continue;
      }
      final rows = library['rows'] as List;
      total += rows.length;
      saved += rows
          .where(
            (row) =>
                _responses['/households/$household/recipes/${row['id']}'] !=
                    null &&
                (pending == null ||
                    (pending['downloaded'] as List).contains(row['id'])),
          )
          .length;
      if (pending != null) complete = false;
    }
    progress.value = RecipeSyncProgress(
      saved: saved,
      total: known ? total : null,
      working: working,
      ready: complete && saved == total && error == null,
      error: error,
    );
  }

  bool _cacheable(String path) =>
      path == '/me' ||
      (!Uri.parse(path).path.endsWith('/recipes/deleted') &&
          RegExp(r'^/households/[^/]+/(people|recipes)(/[^/?]+)?(\?.*)?$')
              .hasMatch(path));

  /// Use the server-confirmed save response immediately, including offline reads.
  Future<void> rememberSavedRecipe(
    String path,
    Map<String, dynamic> data,
  ) async {
    final segments = Uri.parse(path).pathSegments;
    if (segments.length < 3 ||
        segments[0] != 'households' ||
        segments[2] != 'recipes' ||
        segments.length > 5) {
      return;
    }
    // Preview/generation endpoints must never enter the saved recipe cache.
    if (segments.length == 5 &&
        segments[4] != 'delete' &&
        segments[4] != 'restore' &&
        segments[4] != 'attach') {
      return;
    }
    final savedId =
        data['deleted_recipe_id'] ?? (data['recipe'] as Map?)?['id'];
    if (savedId == null || savedId.toString().isEmpty) return;
    await _load();
    if (_closed) return;
    final root = '/households/${segments[1]}/recipes';
    path = '$root/$savedId';
    if (data['deleted_recipe_id'] != null) {
      _accessVersion++;
      final id = '${data['deleted_recipe_id']}';
      _responses.removeWhere(
        (key, _) => Uri.parse(key).path == root || key == '$root/$id',
      );
      final library = _libraries[segments[1]] as Map?;
      (library?['rows'] as List?)?.removeWhere((row) => '${row['id']}' == id);
      if (library != null) {
        library['synced_at'] = '1970-01-01T00:00:00Z';
        library['scopes'] = <String, dynamic>{};
        (library['ids'] as Map).forEach((_, ids) => (ids as List).remove(id));
      }
      _pending.remove(segments[1]);
      for (final entry in _responses.entries.where(
        (entry) => entry.key.startsWith('$root/'),
      )) {
        final recipe = entry.value['recipe'] as Map?;
        for (final key in ['related', 'variation_family', 'pairings']) {
          (recipe?[key] as List?)?.removeWhere((row) => '${row['id']}' == id);
        }
        final remainingFamily = recipe?['variation_family'] as List?;
        if (remainingFamily != null && remainingFamily.isNotEmpty) {
          final representative = remainingFamily.first['id'];
          recipe!['family_representative_id'] = representative;
          for (final row in library?['rows'] as List? ?? []) {
            if ('${row['id']}' == '${recipe['id']}') {
              row['family_representative_id'] = representative;
            }
          }
        }
        (recipe?['edit_options']?['recipes'] as List?)?.removeWhere(
          (row) => '${row['id']}' == id,
        );
      }
      await _save();
      return;
    }
    if (data['recipe'] is! Map) return;
    _accessVersion++;
    final recipe = data['recipe'] as Map<String, dynamic>;
    _responses[path] = jsonDecode(jsonEncode(data));
    for (final member in recipe['variation_family'] as List? ?? []) {
      final cached = _responses['$root/${member['id']}']?['recipe'] as Map?;
      if (cached != null) {
        cached['variation_family'] = jsonDecode(
          jsonEncode(recipe['variation_family']),
        );
        cached['family_representative_id'] = recipe['family_representative_id'];
      }
    }
    final household = segments[1];
    final library = _libraries[household] as Map?;
    if (library != null) {
      if (!(library['rows'] as List).any((row) => row['id'] == recipe['id'])) {
        (library['rows'] as List).add({'id': recipe['id']});
        ((library['ids'] as Map)[''] as List).add(recipe['id']);
      }
      for (final row in library['rows'] as List) {
        if (row['id'] == recipe['id']) {
          for (final field in [
            'title',
            'description',
            'original_language',
            'servings',
            'yield_text',
            'prep_minutes',
            'cook_minutes',
            'total_minutes',
            'parent_recipe_id',
            'is_variation',
            'family_representative_id',
          ]) {
            row[field] = recipe[field];
          }
          final photos = (recipe['photos'] as List? ?? []);
          final covers = photos.where(
            (p) => p['is_cover'] == 1 || p['is_cover'] == true,
          );
          row['photo_url'] = (covers.isNotEmpty
              ? covers.first
              : photos.firstOrNull)?['source_url'];
        }
      }
      // Force the next sync to refresh categories and related recipes as well.
      library['synced_at'] = '1970-01-01T00:00:00Z';
    }
    _responses.removeWhere((key, _) => Uri.parse(key).path == root);
    await _save();
  }

  /// Read saved browse text without waiting for a network timeout.
  Future<Map<String, dynamic>?> cachedBrowse(String path) async {
    await _load();
    final parts = Uri.parse(path).pathSegments;
    if (_closed ||
        parts.length != 3 ||
        parts[0] != 'households' ||
        parts[2] != 'recipes') {
      return null;
    }
    return _cached(path);
  }

  Future<Map<String, dynamic>> request(String path) async {
    await _load();
    if (offlineStatus.value && _cacheable(path)) {
      final cached = _cached(path);
      if (cached != null) return cached;
      throw ApiException(
        503,
        'This content has not been saved on this device yet. Connect to the internet and try again.',
      );
    }
    final version = _accessVersion;
    try {
      final data = await fetch(path);
      if (_closed || version != _accessVersion) return data;
      offlineStatus.value = false;
      if (_cacheable(path)) {
        _responses[path] = data;
        if (path == '/me') {
          _pruneHouseholds(
            (data['households'] as List? ?? [])
                .map((h) => h['id'] as String)
                .toList(),
          );
        }
        await _save();
      }
      return data;
    } on ApiException catch (error) {
      // Authorization, deletion and server errors must never become cache hits.
      if (!_closed) offlineStatus.value = false;
      await _invalidate(path, error.status);
      rethrow;
    } catch (error) {
      if (!isOfflineFailure(error)) rethrow;
      if (!_closed) offlineStatus.value = true;
      final cached = _cacheable(path) ? _cached(path) : null;
      if (cached != null) return cached;
      rethrow;
    }
  }

  void _pruneHouseholds(List<String> households) {
    final current = households.toSet();
    if (!setEquals(_knownHouseholds, current)) {
      _accessVersion++;
      _knownHouseholds = current;
    }
    if (_libraries.keys.any((id) => !households.contains(id)) ||
        _responses.keys.any(
          (path) =>
              path.startsWith('/households/') &&
              !households.contains(Uri.parse(path).pathSegments[1]),
        )) {
      _accessVersion++;
    }
    _libraries.removeWhere((id, _) => !households.contains(id));
    _pending.removeWhere((id, _) => !households.contains(id));
    _syncHouseholds = households;
    _responses.removeWhere(
      (path, _) =>
          path.startsWith('/households/') &&
          !households.contains(Uri.parse(path).pathSegments[1]),
    );
  }

  Future<void> _invalidate(String path, int status) async {
    if (_closed) return;
    if (status == 401 || status == 403) {
      _accessVersion++;
      _responses.clear();
      _libraries.clear();
      _pending.clear();
      await _save();
    } else if (status == 404) {
      _accessVersion++;
      _responses.remove(path);
      final parts = Uri.parse(path).pathSegments;
      if (parts.length >= 3 && parts[2] == 'recipes') {
        _libraries.remove(parts[1]);
        _pending.remove(parts[1]);
      }
      await _save();
    }
  }

  Map<String, dynamic>? _cached(String path) {
    final uri = Uri.parse(path);
    final segments = uri.pathSegments;
    if (segments.length == 3 && segments[2] == 'recipes') {
      final pending = _pending[segments[1]] as Map?;
      final library =
          _libraries[segments[1]] as Map? ??
          (pending == null
              ? null
              : {
                  'rows': (pending['rows'] as List)
                      .where(
                        (row) =>
                            _responses['/households/${segments[1]}/recipes/${row['id']}'] !=
                            null,
                      )
                      .toList(),
                  'ids': {
                    '': (pending['rows'] as List)
                        .where(
                          (row) =>
                              _responses['/households/${segments[1]}/recipes/${row['id']}'] !=
                              null,
                        )
                        .map((row) => row['id'])
                        .toList(),
                  },
                  'scopes': <String, dynamic>{},
                });
      if (library != null) {
        final scope = uri.queryParameters['scope'] ?? '';
        final q = (uri.queryParameters['q'] ?? '').toLowerCase();
        final scopes = library['scopes'] as Map;
        final tree = scopes[scope] as Map?;
        if (q.isEmpty &&
            uri.queryParameters['tree'] == '1' &&
            tree?['view'] == 'categories') {
          return Map<String, dynamic>.from(tree!);
        }
        final ids = (library['ids'] as Map)[scope] as List?;
        if (ids != null) {
          var rows = (library['rows'] as List).where((row) {
            if (!ids.contains(row['id'])) return false;
            final detail =
                _responses['/households/${segments[1]}/recipes/${row['id']}'];
            final recipe = detail?['recipe'] as Map?;
            final searchable = [
              row['title'],
              row['description'],
              for (final ingredient in recipe?['ingredients'] as List? ?? [])
                ingredient['ingredient_name'],
              for (final tag in recipe?['tags'] as List? ?? []) tag['label'],
              for (final tree in scopes.values)
                for (final node in tree['category_nodes'] as List? ?? [])
                  if (((library['ids'] as Map)[node['id']] as List? ?? [])
                      .contains(row['id']))
                    node['label'],
            ].join(' ').toLowerCase();
            return searchable.contains(q);
          }).toList();
          if (uri.queryParameters['families'] == '1') {
            final representatives = rows
                .map(
                  (row) =>
                      '${row['family_representative_id'] ?? row['parent_recipe_id'] ?? row['id']}',
                )
                .toSet();
            rows = (library['rows'] as List)
                .where((row) => representatives.contains('${row['id']}'))
                .toList();
          }
          final offset =
              int.tryParse(uri.queryParameters['offset'] ?? '0') ?? 0;
          return {
            'recipes': rows.skip(offset).take(30).toList(),
            'category_nodes': [],
            'view': 'recipes',
            'next_offset': offset + 30 < rows.length ? offset + 30 : null,
          };
        }
      }
    }
    final data = _responses[path];
    return data == null ? null : Map<String, dynamic>.from(data as Map);
  }

  Future<void> sync(List<String> households) =>
      _sync ??= _synchronize(households).whenComplete(() => _sync = null);

  Future<void> retry() async {
    if (offlineStatus.value) await _probe();
    if (!_closed && !offlineStatus.value) {
      await sync(_knownHouseholds?.toList() ?? []);
    }
  }

  Future<void> _synchronize(List<String> households) async {
    await _load();
    if (_closed) return;
    _pruneHouseholds(households);
    final accessVersion = _accessVersion;
    _updateProgress(working: !offlineStatus.value);
    Future<List<dynamic>> pages(String root, String scope) async {
      final items = <dynamic>[];
      int? offset = 0;
      do {
        if (_closed || offlineStatus.value || accessVersion != _accessVersion) {
          throw StateError('Sync stopped');
        }
        final data = await fetch(
          '$root?offset=$offset${scope.isEmpty ? '' : '&scope=$scope'}',
        );
        if (_closed || accessVersion != _accessVersion) {
          throw StateError('Sync stopped');
        }
        items.addAll(data['recipes'] as List);
        offset = data['next_offset'] as int?;
      } while (offset != null);
      return items;
    }

    try {
      Object? textFailure;
      // Text takes priority over optional category and household metadata.
      for (final household in households) {
        if (_closed || offlineStatus.value) break;
        final root = '/households/$household/recipes';
        final previous = _libraries[household] as Map?;
        final lastSync = DateTime.tryParse('${previous?['synced_at']}');
        final fresh =
            lastSync != null &&
            DateTime.now().difference(lastSync) < const Duration(hours: 24);
        // Always check the inventory: a recent snapshot may lack newly added recipes.
        final rows = await pages(root, '');
        if (_closed || accessVersion != _accessVersion) return;
        final inventoryIds = rows.map((row) => row['id']).toSet();
        final removed = (previous?['rows'] as List? ?? []).any(
          (row) => !inventoryIds.contains(row['id']),
        );
        if (removed && previous != null) {
          previous['scopes'] = <String, dynamic>{};
          (previous['ids'] as Map).forEach(
            (_, ids) =>
                (ids as List).removeWhere((id) => !inventoryIds.contains(id)),
          );
          for (final entry in _responses.entries.where(
            (entry) => entry.key.startsWith('$root/'),
          )) {
            final recipe = entry.value['recipe'] as Map?;
            for (final key in ['related', 'variation_family', 'pairings']) {
              (recipe?[key] as List?)?.removeWhere(
                (row) => !inventoryIds.contains(row['id']),
              );
            }
            (recipe?['edit_options']?['recipes'] as List?)?.removeWhere(
              (row) => !inventoryIds.contains(row['id']),
            );
          }
        }
        (previous?['rows'] as List?)?.removeWhere(
          (row) => !inventoryIds.contains(row['id']),
        );
        _responses.removeWhere(
          (path, _) =>
              (removed && Uri.parse(path).path == root) ||
              (path.startsWith('$root/') &&
                  !inventoryIds.contains(Uri.parse(path).pathSegments.last)),
        );
        await _save(required: true);
        final previousRows = {
          for (final row in previous?['rows'] as List? ?? []) row['id']: row,
        };
        final oldPending = _pending[household] as Map?;
        final started = DateTime.tryParse('${oldPending?['started_at']}');
        final resumable =
            started != null &&
            DateTime.now().difference(started) < const Duration(hours: 24);
        final downloaded = resumable
            ? List<dynamic>.from(oldPending!['downloaded'] as List)
            : fresh && oldPending == null
            ? rows
                  .where(
                    (row) =>
                        jsonEncode(previousRows[row['id']]) ==
                            jsonEncode(row) &&
                        _responses['$root/${row['id']}'] != null,
                  )
                  .map((row) => row['id'])
                  .toList()
            : <dynamic>[];
        downloaded.removeWhere(
          (id) =>
              !rows.any((row) => row['id'] == id) ||
              _responses['$root/$id'] == null,
        );
        final pending = {
          'rows': rows,
          'downloaded': downloaded,
          'started_at': (resumable ? started : DateTime.now())
              .toUtc()
              .toIso8601String(),
        };
        _pending[household] = pending;
        await _save(required: true);
        _updateProgress(working: true);
        final missing = rows
            .where((row) => !downloaded.contains(row['id']))
            .toList();
        Object? failure;
        var disconnected = false;
        for (var start = 0; start < missing.length; start += 3) {
          if (_closed || offlineStatus.value) break;
          final batch = missing.skip(start).take(3).toList();
          final details = await Future.wait(
            batch.map((row) async {
              try {
                final data = await fetch('$root/${row['id']}');
                if (data['recipe'] is! Map) {
                  throw const FormatException('Missing recipe text');
                }
                return data;
              } catch (error) {
                if (error is ApiException &&
                    [401, 403].contains(error.status)) {
                  rethrow;
                }
                failure ??= error;
                if (isOfflineFailure(error)) disconnected = true;
                return null;
              }
            }),
          );
          if (_closed || accessVersion != _accessVersion) return;
          for (var i = 0; i < batch.length; i++) {
            if (details[i] != null) {
              _responses['$root/${batch[i]['id']}'] = details[i];
              downloaded.add(batch[i]['id']);
            }
          }
          // Persist even the first batch, including successful peers of a failed request.
          await _save(required: true);
          _updateProgress(working: true);
          if (disconnected) {
            offlineStatus.value = true;
            break;
          }
        }
        if (downloaded.length != rows.length) {
          textFailure ??= failure ?? StateError('Recipe download interrupted');
          continue;
        }
        final currentIds = rows.map((row) => row['id']).toSet();
        final sameInventory =
            fresh && setEquals(previousRows.keys.toSet(), currentIds);
        _responses.removeWhere(
          (path, _) =>
              path.startsWith('$root/') &&
              !currentIds.contains(Uri.parse(path).pathSegments.last),
        );
        _libraries[household] = {
          'rows': rows,
          'ids': sameInventory ? previous!['ids'] : {'': currentIds.toList()},
          'scopes': sameInventory ? previous!['scopes'] : <String, dynamic>{},
          'synced_at': (fresh ? lastSync : DateTime.now())
              .toUtc()
              .toIso8601String(),
        };
        _pending.remove(household);
        try {
          await _save(required: true);
        } catch (_) {
          _pending[household] = pending;
          if (previous == null) {
            _libraries.remove(household);
          } else {
            _libraries[household] = previous;
          }
          rethrow;
        }
        _updateProgress(working: true);
      }
      _updateProgress(
        error: textFailure == null ? null : 'Recipe download paused. Saved text will be kept and missing recipes retried.',
      );
      // A category or people request cannot prevent saving the recipe database.
      for (final household in households) {
        if (_closed || offlineStatus.value || accessVersion != _accessVersion) {
          return;
        }
        final library = _libraries[household] as Map?;
        if (library == null || (library['scopes'] as Map).containsKey('')) {
          continue;
        }
        final root = '/households/$household/recipes';
        final ids = Map<String, dynamic>.from(library['ids'] as Map);
        final scopes = <String, dynamic>{};
        final queue = <String>[''];
        try {
          for (var index = 0; index < queue.length; index++) {
            final scope = queue[index];
            final tree = await fetch(
              '$root?tree=1&families=1${scope.isEmpty ? '' : '&scope=$scope'}',
            );
            if (_closed || accessVersion != _accessVersion) return;
            scopes[scope] = tree;
            if (scope.isNotEmpty) {
              ids[scope] = (await pages(
                root,
                scope,
              )).map((row) => row['id']).toList();
            }
            for (final node in tree['category_nodes'] as List? ?? []) {
              final id = node['id'] as String;
              if (!queue.contains(id)) queue.add(id);
            }
          }
          library['ids'] = ids;
          library['scopes'] = scopes;
          await _save(required: true);
          final peoplePath = '/households/$household/people';
          final people = await fetch(peoplePath);
          if (_closed || accessVersion != _accessVersion) return;
          _responses[peoplePath] = people;
          await _save();
        } catch (error) {
          if (error is ApiException && [401, 403].contains(error.status)) {
            rethrow;
          }
          if (isOfflineFailure(error)) offlineStatus.value = true;
        }
      }
    } catch (error) {
      if (error is ApiException && [401, 403].contains(error.status)) {
        await _invalidate('/me', error.status);
      }
      if (!_closed && isOfflineFailure(error)) offlineStatus.value = true;
      _updateProgress(
        error: error is OfflineStorageException
            ? 'Could not save recipes on this device. Free up storage and retry.'
            : error is ApiException
            ? error.message
            : 'Recipe download paused. It will resume when connected; you can also retry.',
      );
    }
  }

  void close() {
    _closed = true;
    _connection?.cancel();
    _retry?.cancel();
    if (_reconnect != null) WidgetsBinding.instance.removeObserver(this);
  }
}

class RecipeSyncStatus extends StatelessWidget {
  const RecipeSyncStatus({
    super.key,
    required this.progress,
    required this.retry,
  });
  final ValueListenable<RecipeSyncProgress> progress;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<RecipeSyncProgress>(
        valueListenable: progress,
        builder: (context, state, _) {
          if (state.ready) return const SizedBox.shrink();
          final text =
              state.error ??
              (state.working
                  ? 'Preparing recipes for offline use…'
                  : 'Offline download paused');
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Row(
              children: [
                Icon(
                  state.ready
                      ? Icons.offline_pin_outlined
                      : Icons.download_outlined,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (!state.ready && !state.working)
                  TextButton(onPressed: retry, child: const Text('Retry')),
              ],
            ),
          );
        },
      );
}

class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: offlineStatus,
    builder: (context, offline, _) => offline
        ? Tooltip(
            message: 'Offline · showing saved recipes',
            child: Semantics(
              label: 'Offline. Showing saved recipes.',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off_outlined, size: 14),
                      SizedBox(width: 4),
                      Text('Offline', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}
