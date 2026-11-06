import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'client_log.dart';
import 'offline_store.dart';

typedef SendChange = Future<Map<String, dynamic>> Function(
  String path,
  Map<String, dynamic> body,
);

/// Only the requested offline exceptions. Never participates in socket readiness.
class OfflineChanges extends ChangeNotifier {
  OfflineChanges({
    required this.account,
    this.read = readOfflineStore,
    this.write = writeOfflineStore,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final String account;
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final DateTime Function() now;
  String get key => 'offline-actions-$account';
  final List<Map<String, dynamic>> _entries = [];
  Future<void>? _loaded;
  Future<void> _disk = Future.value();
  bool _sending = false;
  List<Map<String, dynamic>> get recipes =>
      _entries.where((e) => e['kind'] == 'recipe').map(_copy).toList();
  bool get hasAutomatic =>
      _entries.any((e) => e['kind'] == 'remove' || e['create'] == true);
  Duration? get untilRemovalExpiry {
    final removals = _entries.where((e) => e['kind'] == 'remove');
    if (removals.isEmpty) return null;
    final at = removals.map((e) => e['at'] as int).reduce(min);
    return Duration(
      milliseconds: max(
        0,
        at +
            const Duration(hours: 2).inMilliseconds -
            now().millisecondsSinceEpoch,
      ),
    );
  }

  static Map<String, dynamic> _copy(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  static String newId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> load() => _loaded ??= () async {
    try {
      final text = await read(key);
      if (text != null && text.isNotEmpty) {
        final saved = (jsonDecode(text) as List)
            .map((e) => _copy(e as Map))
            .toList();
        _entries
          ..clear()
          ..addAll(saved);
      }
      await expire();
    } catch (_) {
      _loaded = null;
      rethrow;
    }
  }();

  Future<void> _persist() {
    final value = jsonEncode(_entries);
    final task = _disk.catchError((Object _) {}).then((_) async {
      try {
        await write(key, value);
      } catch (error) {
        clientLog.record('offline', 'persist_failed', error: error);
        throw ApiException(
          507,
          'Could not save on this device. Free storage and retry.',
          code: 'storage_failure',
        );
      }
    });
    _disk = task;
    return task;
  }

  Future<void> expire() async {
    final before = _entries.length;
    _entries.removeWhere(
      (e) =>
          e['kind'] == 'remove' &&
          now().millisecondsSinceEpoch - (e['at'] as int) >=
              const Duration(hours: 2).inMilliseconds,
    );
    if (_entries.length != before) {
      await _persist();
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> saveRecipe(
    String path,
    Map<String, dynamic> body, {
    required bool connected,
    required SendChange send,
  }) async {
    await load();
    final payload = _copy(body)..remove('revision');
    final create = RegExp(r'/recipes$').hasMatch(path);
    if (create) {
      payload.putIfAbsent('client_save_id', newId);
    } else {
      payload.remove('client_save_id');
    }
    if (connected) {
      try {
        return await send(path, payload);
      } catch (error) {
        if (!isTemporaryCommunicationFailure(error)) rethrow;
      }
    }
    final entryId = create ? payload['client_save_id'] as String : newId();
    final previous = !create
        ? _entries
              .where((e) => e['kind'] == 'recipe' && e['path'] == path)
              .toList()
        : <Map<String, dynamic>>[];
    if (!create) {
      _entries.removeWhere((e) => e['kind'] == 'recipe' && e['path'] == path);
    }
    _entries.add({
      'id': entryId,
      'kind': 'recipe',
      'path': path,
      'body': payload,
      'create': create,
    });
    try {
      await _persist();
    } catch (_) {
      _entries.removeWhere((e) => e['id'] == entryId);
      _entries.addAll(previous);
      rethrow;
    }
    notifyListeners();
    clientLog.record(
      'offline',
      create ? 'recipe_add_retained' : 'recipe_edit_retained',
      path: path,
    );
    return {
      'recipe': {...body, '_offline_pending': true},
      '_offline_pending': true,
    };
  }

  Future<void> removeItems(String path, Iterable<String> ids) async {
    await load();
    final added = <String>[];
    for (final id in ids) {
      if (_entries.any(
        (e) => e['kind'] == 'remove' && e['path'] == path && e['item'] == id,
      )) {
        continue;
      }
      final entryId = newId();
      added.add(entryId);
      _entries.add({
        'id': entryId,
        'kind': 'remove',
        'path': path,
        'item': id,
        'at': now().millisecondsSinceEpoch,
      });
    }
    try {
      await _persist();
    } catch (_) {
      _entries.removeWhere((e) => added.contains(e['id']));
      rethrow;
    }
    notifyListeners();
  }

  Map<String, dynamic> shopping(String path, Map<String, dynamic> server) {
    final ids = _entries
        .where(
          (e) =>
              e['kind'] == 'remove' &&
              e['path'] == path &&
              now().millisecondsSinceEpoch - (e['at'] as int) <
                  const Duration(hours: 2).inMilliseconds,
        )
        .map((e) => e['item'])
        .toSet();
    return {
      ...server,
      'items': [
        for (final item in server['items'] as List)
          if (!ids.contains((item as Map)['id'])) item,
      ],
    };
  }

  Future<void> discard(String id) async {
    final removed = _entries.where((e) => e['id'] == id).toList();
    _entries.removeWhere((e) => e['id'] == id);
    try {
      await _persist();
    } catch (_) {
      _entries.addAll(removed);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> submit(Map<String, dynamic> entry, SendChange send) async {
    await send(entry['path'] as String, _copy(entry['body'] as Map));
    await discard(entry['id'] as String);
  }

  Future<void> sendAutomatic(
    SendChange send,
    bool Function() connected, {
    void Function(Map<String, dynamic>, Object)? onFailure,
  }) async {
    await load();
    if (_sending) return;
    _sending = true;
    try {
      await expire();
      for (final entry in _entries.map(_copy).toList()) {
        if (!connected()) break;
        if (entry['kind'] != 'remove' && entry['create'] != true) continue;
        try {
          if (entry['kind'] == 'remove') {
            await send(entry['path'] as String, {
              'remove_ids': [entry['item']],
            });
            await discard(entry['id'] as String);
          } else {
            await submit(entry, send);
          }
        } catch (error) {
          clientLog.record(
            'offline',
            'send_failed',
            path: entry['path'] as String,
            error: error,
            code: error is ApiException ? error.code : null,
          );
          onFailure?.call(entry, error);
          // Each action is independent. Other actions and incoming pushes continue.
        }
      }
    } finally {
      _sending = false;
    }
  }
}
