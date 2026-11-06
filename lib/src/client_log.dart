import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'offline_store.dart';

/// Device-local diagnostics only. Never record payloads, tokens or exception
/// messages: those may contain credentials, recipe text or personal data.
class ClientLog extends ChangeNotifier {
  ClientLog({
    this.read = readOfflineStore,
    this.write = writeOfflineStore,
    this.now = DateTime.now,
    this.limit = 300,
  }) : assert(limit > 0);

  static const _key = 'client-diagnostics-v1';
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String) write;
  final DateTime Function() now;
  final int limit;
  final _rows = <Map<String, dynamic>>[];
  Future<void>? _start;
  Future<void> _writes = Future.value();
  String? version;
  bool _saveScheduled = false;
  bool _notifying = false, _disposed = false;

  Future<void> start() => _start ??= _load();
  Future<void> _load() async {
    try {
      final raw = await read(_key).timeout(const Duration(seconds: 2));
      if (raw != null) {
        final old = (jsonDecode(raw) as List)
            .whereType<Map>()
            .where(
              (r) =>
                  r['error'] != null ||
                  (r['status'] is int &&
                      (r['status'] as int) >= 400 &&
                      (r['status'] as int) < 600),
            )
            .map((r) => Map<String, dynamic>.from(r));
        _rows.insertAll(0, old);
        _trim();
      }
    } catch (_) {
      // Diagnostics must never prevent the app or synchronization from starting.
    }
    _changed();
    if (_rows.isNotEmpty) _scheduleSave();
  }

  static String _label(String value) =>
      RegExp(r'^[a-zA-Z0-9_.:-]{1,80}$').hasMatch(value) ? value : 'redacted';

  static String route(String value) {
    List<String> parts;
    try {
      parts = Uri.tryParse(value)?.pathSegments ?? const <String>[];
    } catch (_) {
      return '/invalid-route';
    }
    const names = {
      'me',
      'households',
      'recipes',
      'snapshot',
      'shopping-list',
      'sync-request',
      'meal-plan',
      'people',
      'name',
      'favorites',
      'restaurants',
      'history',
      'cooking-sessions',
      'timers',
      'timer-devices',
      'remove',
      'child-mode',
      'share',
      'step',
      'timer',
      'presence',
      'join',
      'end',
      'photos',
      'account',
      'recipe-blank',
      'edit-options',
      'verification-email',
      'invitations',
      'respond',
      'admin',
      'users',
      'recipe-chat',
      'recipe-import',
    };
    return '/${parts.map((p) => names.contains(p) ? p : ':id').join('/')}';
  }

  void record(
    String area,
    String event, {
    Object? error,
    StackTrace? stack,
    String? path,
    String? code,
    int? status,
    int? pending,
    int? attempt,
    bool? connected,
    bool? confirmed,
  }) {
    if (_disposed ||
        (error == null && (status == null || status < 400 || status >= 600))) {
      return;
    }
    final failureCode =
        code ??
        switch (error) {
          FirebaseException e => e.code,
          PlatformException e => e.code,
          _ => null,
        };
    _rows.add({
      'time': now().toUtc().toIso8601String(),
      'area': _label(area),
      'event': _label(event),
      if (version != null) 'version': version,
      if (error != null) 'error': _label(error.runtimeType.toString()),
      if (path != null) 'route': route(path),
      if (failureCode != null) 'code': _label(failureCode),
      'status': ?status,
      'pending': ?pending,
      'attempt': ?attempt,
      'connected': ?connected,
      'confirmed': ?confirmed,
      if (stack != null)
        'locations': RegExp(r'[A-Za-z0-9_]+\.dart:\d+(?::\d+)?')
            .allMatches(stack.toString())
            .take(8)
            .map((m) => m[0])
            .toList(),
    });
    _trim();
    _changed();
    if (_start != null) _scheduleSave();
  }

  void _scheduleSave() {
    if (_saveScheduled || _disposed) return;
    _saveScheduled = true;
    scheduleMicrotask(() {
      _saveScheduled = false;
      if (!_disposed) unawaited(flush());
    });
  }

  void _trim() {
    while (_rows.length > limit ||
        utf8.encode(jsonEncode(_rows)).length > 128 * 1024) {
      _rows.removeAt(0);
    }
  }

  String get text =>
      _rows.isEmpty ? 'No errors recorded.' : _rows.map(jsonEncode).join('\n');

  void _changed() {
    if (_notifying || _disposed) return;
    _notifying = true;
    scheduleMicrotask(() {
      _notifying = false;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> flush() async {
    await start();
    final data = jsonEncode(_rows);
    _writes = _writes.then((_) async {
      try {
        await write(_key, data).timeout(const Duration(seconds: 2));
      } catch (_) {
        // Keep the in-memory log available even when device storage fails.
      }
    });
    await _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final clientLog = ClientLog();
