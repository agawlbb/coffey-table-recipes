/// Overlay only queued user edits on a fresh list, preserving unrelated items.
Map<String, dynamic> overlayShoppingChanges(
  Map<String, dynamic> server,
  Iterable<Map<String, dynamic>> changes,
) {
  final items = [
    for (final row in server['items'] as List)
      Map<String, dynamic>.from(row as Map),
  ];
  var pending = 0;
  for (final change in changes) {
    final body = change['body'] as Map;
    if (body['base_items'] is! List) continue;
    pending++;
    final base = {
      for (final row in body['base_items'] as List) '${row['id']}': row as Map,
    };
    final wanted = {
      for (final row in body['items'] as List) '${row['id']}': row as Map,
    };
    items.removeWhere(
      (row) =>
          base.containsKey('${row['id']}') &&
          !wanted.containsKey('${row['id']}'),
    );
    for (final entry in wanted.entries) {
      final previous = base[entry.key];
      final index = items.indexWhere((row) => '${row['id']}' == entry.key);
      if (previous == null) {
        if (index < 0) items.add(Map<String, dynamic>.from(entry.value));
        continue;
      }
      final edits = <String, dynamic>{
        for (final field in ['name', 'note', 'checked', 'department'])
          if (entry.value.containsKey(field) &&
              entry.value[field] != previous[field])
            field: entry.value[field],
      };
      if (edits.isEmpty) continue;
      if (index < 0) {
        items.add(Map<String, dynamic>.from(entry.value));
      } else {
        items[index] = {...items[index], ...edits};
      }
    }
    final baseOrder = base.keys.where(wanted.containsKey).toList();
    final wantedOrder = wanted.keys.where(base.containsKey).toList();
    String? anchor;
    for (final id in wanted.keys) {
      final index = items.indexWhere((row) => '${row['id']}' == id);
      if (index < 0) continue;
      if (!base.containsKey(id) ||
          baseOrder.indexOf(id) != wantedOrder.indexOf(id)) {
        final item = items.removeAt(index);
        final at = anchor == null
            ? -1
            : items.indexWhere((row) => '${row['id']}' == anchor);
        items.insert(anchor != null && at < 0 ? items.length : at + 1, item);
      }
      anchor = id;
    }
  }
  return {
    ...server,
    'items': items,
    'revision': (server['revision'] as int) + pending,
  };
}
