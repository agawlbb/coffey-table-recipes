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
      await fetch('/me');
      if (_closed) return;
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
      if (offlineStatus.value &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_probe());
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
      }
    } catch (_) {
      /* A missing/corrupt cache must not prevent online use. */
    }
  }();

  Future<void> _save() {
    final source = jsonEncode({
      'responses': _responses,
      'libraries': _libraries,
    });
    return _writes = _writes.then((_) async {
      try {
        await write(key, source);
      } catch (_) {
        /* Storage may be full. */
      }
    });
  }

  bool _cacheable(String path) =>
      path == '/me' ||
      RegExp(r'^/households/[^/]+/(people|recipes)(/[^/?]+)?(\?.*)?$')
          .hasMatch(path);

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
    try {
      final data = await fetch(path);
      if (_closed) return data;
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
      await _save();
    } else if (status == 404) {
      _accessVersion++;
      _responses.remove(path);
      final parts = Uri.parse(path).pathSegments;
      if (parts.length >= 3 && parts[2] == 'recipes') {
        _libraries.remove(parts[1]);
      }
      await _save();
    }
  }

  Map<String, dynamic>? _cached(String path) {
    final uri = Uri.parse(path);
    final segments = uri.pathSegments;
    if (segments.length == 3 && segments[2] == 'recipes') {
      final library = _libraries[segments[1]] as Map?;
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
          final rows = (library['rows'] as List).where((row) {
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

  Future<void> _synchronize(List<String> households) async {
    await _load();
    final accessVersion = _accessVersion;
    try {
      for (final household in households) {
        if (_closed || offlineStatus.value) return;
        final root = '/households/$household/recipes';
        final lastSync = DateTime.tryParse(
          '${(_libraries[household] as Map?)?['synced_at']}',
        );
        if (lastSync != null &&
            DateTime.now().difference(lastSync) < const Duration(hours: 24)) {
          continue;
        }
        final rows = <dynamic>[];
        final ids = <String, List<dynamic>>{};
        final scopes = <String, dynamic>{};
        Future<List<dynamic>> pages(String scope) async {
          final items = <dynamic>[];
          int? offset = 0;
          do {
            if (_closed || offlineStatus.value) {
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

        rows.addAll(await pages(''));
        ids[''] = rows.map((r) => r['id']).toList();
        final queue = <String>[''];
        for (var index = 0; index < queue.length; index++) {
          final scope = queue[index];
          if (_closed || offlineStatus.value) return;
          final tree = await fetch(
            '$root?tree=1${scope.isEmpty ? '' : '&scope=$scope'}',
          );
          if (_closed || accessVersion != _accessVersion) return;
          scopes[scope] = tree;
          if (scope.isNotEmpty) {
            ids[scope] = (await pages(scope)).map((r) => r['id']).toList();
          }
          for (final node in tree['category_nodes'] as List? ?? []) {
            final id = node['id'] as String;
            if (!queue.contains(id)) queue.add(id);
          }
        }
        for (var start = 0; start < rows.length; start += 3) {
          if (_closed || offlineStatus.value) return;
          final batch = rows.skip(start).take(3).toList();
          final details = await Future.wait(
            batch.map((row) => fetch('$root/${row['id']}')),
          );
          if (_closed || accessVersion != _accessVersion) return;
          for (var i = 0; i < batch.length; i++) {
            _responses['$root/${batch[i]['id']}'] = details[i];
          }
          if ((start + batch.length) ~/ 25 > start ~/ 25) await _save();
        }
        final currentIds = ids['']!.toSet();
        _responses.removeWhere(
          (path, _) =>
              path.startsWith('$root/') &&
              !currentIds.contains(Uri.parse(path).pathSegments.last),
        );
        // Publish the new index only after every detail and category succeeds.
        _libraries[household] = {
          'rows': rows,
          'ids': ids,
          'scopes': scopes,
          'synced_at': DateTime.now().toUtc().toIso8601String(),
        };
        final peoplePath = '/households/$household/people';
        final people = await fetch(peoplePath);
        if (_closed || accessVersion != _accessVersion) return;
        _responses[peoplePath] = people;
        await _save();
      }
      _pruneHouseholds(households);
      await _save();
    } catch (error) {
      if (error is ApiException) await _invalidate('/me', error.status);
      if (!_closed && isOfflineFailure(error)) offlineStatus.value = true;
      // Retry on the next launch, refresh or connection change.
    }
  }

  void close() {
    _closed = true;
    _connection?.cancel();
    _retry?.cancel();
    if (_reconnect != null) WidgetsBinding.instance.removeObserver(this);
  }
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
