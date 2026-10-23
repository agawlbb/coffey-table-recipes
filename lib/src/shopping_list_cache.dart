import 'dart:convert';

import 'offline_store.dart';

/// One account/server/household snapshot; never stores optimistic edits.
class ShoppingListCache {
  ShoppingListCache({
    required String account,
    required String household,
    required String server,
    this.readStore = readOfflineStore,
    this.writeStore = writeOfflineStore,
  }) : key = 'shopping-list-v1-${jsonEncode([server, account, household])}';

  final String key;
  final Future<String?> Function(String) readStore;
  final Future<void> Function(String, String) writeStore;
  static final _pending = <String, Future<void>>{};

  Future<Map<String, dynamic>?> read() async {
    try {
      await _pending[key];
      final text = await readStore(key);
      if (text == null || text.isEmpty) return null;
      final data = jsonDecode(text) as Map<String, dynamic>;
      final revision = data['revision'];
      final departments = data['departments'] as List;
      final items = data['items'] as List;
      if (revision is! int ||
          revision < 0 ||
          departments.length > 50 ||
          items.length > 500 ||
          departments.any((d) => d is! String || d.isEmpty || d.length > 60) ||
          departments.toSet().length != departments.length) {
        return null;
      }
      final ids = <String>{};
      for (final value in items) {
        final item = value as Map;
        if (item['id'] is! String ||
            !ids.add(item['id'] as String) ||
            item['name'] is! String ||
            (item['name'] as String).trim().isEmpty ||
            (item['name'] as String).length > 200 ||
            (item.containsKey('note') &&
                (item['note'] is! String ||
                    (item['note'] as String).length > 500)) ||
            item['checked'] is! bool ||
            item['department'] is! String ||
            (item['department'] != '' &&
                !departments.contains(item['department']))) {
          return null;
        }
      }
      return data;
    } catch (_) {
      // Unavailable storage or a damaged cache must never prevent a refresh.
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> data) => _write(
    jsonEncode({
      'revision': data['revision'],
      'items': data['items'],
      'departments': data['departments'],
    }),
  );

  Future<void> clear() => _write('');

  Future<void> _write(String value, {String? storageKey}) {
    final target = storageKey ?? key;
    final task = (_pending[target] ?? Future<void>.value()).then((_) async {
      try {
        await writeStore(target, value);
      } catch (_) {
        /* Keep server access working. */
      }
    });
    _pending[target] = task;
    return task.whenComplete(() {
      if (identical(_pending[target], task)) _pending.remove(target);
    });
  }
}
