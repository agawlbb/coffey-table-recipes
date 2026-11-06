import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'client_log.dart';
import 'offline_store.dart';

final offlineStatus = ValueNotifier<bool>(false);
bool get mobileOfflineEnabled =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
typedef OfflineRequest = Future<Map<String, dynamic>> Function(String path);

/// Read-only public links. Authenticated app data belongs to LocalData/SQLite.
class OfflineRecipes {
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
  final Map<String, dynamic> _responses = {};
  Future<void>? _loaded;
  bool _closed = false;
  bool _public(String path) => RegExp(r'^/recipes/[1-9][0-9]*$').hasMatch(path);
  Future<void> _load() => _loaded ??= () async {
    try {
      final text = await read(key).timeout(const Duration(seconds: 2));
      if (text != null) {
        final old = (jsonDecode(text) as Map)['responses'] as Map? ?? {};
        for (final entry in old.entries) {
          if (_public(entry.key as String)) {
            _responses.putIfAbsent(entry.key as String, () => entry.value);
          }
        }
      }
    } catch (error) {
      clientLog.record('storage', 'public_cache_read_failed', error: error);
    }
  }();
  Future<Map<String, dynamic>?> cachedRead(String path) async {
    if (!_public(path) || _closed) return null;
    await _load();
    final value = _responses[path];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  void _save() {
    if (_closed) return;
    unawaited(
      write(
        key,
        jsonEncode({'responses': _responses}),
      ).timeout(const Duration(seconds: 2)).catchError((Object error) {
        clientLog.record('storage', 'public_cache_write_failed', error: error);
      }),
    );
  }

  Future<Map<String, dynamic>> request(String path) async {
    if (!_public(path)) throw ArgumentError('Public recipe path required');
    try {
      final result = await fetch(path);
      if (!_closed) {
        _responses[path] = result;
        _save();
      }
      return result;
    } catch (error) {
      if (isTemporaryCommunicationFailure(error)) {
        final saved = await cachedRead(path);
        if (saved != null) return {...saved, '_cache_needs_refresh': true};
      } else {
        await _load();
        _responses.remove(path);
        _save();
      }
      rethrow;
    }
  }

  void close() {
    _closed = true;
  }
}

class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: offlineStatus,
    builder: (context, offline, _) => offline
        ? Tooltip(
            message: 'Sync paused. Showing saved recipes; the recipe service may be temporarily unavailable.',
            child: Semantics(
              label: 'Sync paused. Showing saved recipes.',
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
                      Text('Sync paused', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}
