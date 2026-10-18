import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'shopping_item_id.dart';

const shoppingDepartments = [
  'Other',
  'Produce',
  'Dairy & eggs',
  'Meat & seafood',
  'Bakery',
  'Pantry',
  'Frozen',
  'Deli',
  'Drinks',
  'Household',
];

typedef ShoppingRequest = Future<Map<String, dynamic>> Function(
  String path, {
  Map<String, dynamic>? body,
});

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({
    super.key,
    required this.householdId,
    required this.householdName,
    required this.request,
  });
  final String householdId;
  final String householdName;
  final ShoppingRequest request;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen>
    with WidgetsBindingObserver {
  final _name = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _confirmedItems = [];
  final _writes =
      <({List<Map<String, dynamic>> items, Completer<bool> done})>[];
  String _department = 'Other';
  int _revision = 0;
  bool _loading = true, _saving = false, _reading = false;
  bool _dragging = false;
  String? _error;
  Timer? _poll;
  String get _path => '/households/${widget.householdId}/shopping-list';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        _load(quiet: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(quiet: true);
  }

  void _accept(Map<String, dynamic> data) {
    _revision = data['revision'] as int;
    _items = (data['items'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    _confirmedItems = _items;
  }

  Future<void> _load({bool quiet = false}) async {
    if (_saving || _reading || _dragging) return;
    _reading = true;
    final revision = _revision;
    try {
      final data = await widget.request(_path);
      if (mounted &&
          !_saving &&
          !_dragging &&
          revision == _revision &&
          (_loading ||
              data['revision'] != _revision ||
              (!quiet && _error != null))) {
        setState(() {
          _accept(data);
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && (!quiet || _items.isEmpty)) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Could not load the shopping list.',
        );
      }
    } finally {
      _reading = false;
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<bool> _save(List<Map<String, dynamic>> items) {
    final done = Completer<bool>();
    final start = !_saving;
    _writes.add((items: items, done: done));
    // ReorderableList expects the new order synchronously on drop. Keep that
    // order visible while serializing writes against the server revision.
    setState(() {
      _items = items;
      _saving = true;
      _error = null;
    });
    if (start) unawaited(_drainWrites());
    return done.future;
  }

  Future<void> _drainWrites() async {
    while (_writes.isNotEmpty) {
      final write = _writes.first;
      try {
        final data = await widget.request(
          _path,
          body: {'revision': _revision, 'items': write.items},
        );
        _revision = data['revision'] as int;
        _confirmedItems = (data['items'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _writes.removeAt(0);
        if (!write.done.isCompleted) write.done.complete(true);
      } catch (error) {
        if (error is ApiException && error.status == 409) {
          try {
            final data = await widget.request(_path);
            _revision = data['revision'] as int;
            _confirmedItems = (data['items'] as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
          } catch (_) {
            /* Retain the last confirmed state if refresh fails. */
          }
        }
        for (final pending in _writes) {
          if (!pending.done.isCompleted) pending.done.complete(false);
        }
        _writes.clear();
        if (mounted) {
          setState(() {
            _items = _confirmedItems;
            _error = error is ApiException
                ? error.message
                : 'Could not save the shopping list. Please try again.';
          });
        }
      }
      if (!mounted) {
        for (final pending in _writes) {
          if (!pending.done.isCompleted) pending.done.complete(false);
        }
        _writes.clear();
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _focus.requestFocus();
      return;
    }
    if (name.length > 200 || _items.length >= 500) return;
    final saved = await _save([
      ..._items,
      {
        'id': newShoppingItemId(),
        'name': name,
        'department': _department,
        'checked': false,
      },
    ]);
    if (saved && mounted) {
      _name.clear();
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _rows => [
    for (final department in [
      ...shoppingDepartments.where((d) => d != 'Other'),
      'Other',
    ]) ...[
      {'heading': department},
      ..._items.where((item) => item['department'] == department),
      if (!_items.any((item) => item['department'] == department))
        {'empty': department},
    ],
  ];

  Widget _shoppingList(bool busy) {
    final colors = Theme.of(context).colorScheme;
    final rows = _rows;
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      onReorderStart: (_) => _dragging = true,
      onReorderEnd: (_) => _dragging = false,
      onReorderItem: (oldIndex, newIndex) {
        if (_loading || !rows[oldIndex].containsKey('id')) return;
        final moved = [...rows];
        final item = moved.removeAt(oldIndex);
        // Keep the first heading above every item, even for a drop at the top.
        moved.insert(newIndex.clamp(1, moved.length), item);
        var department = '';
        final items = <Map<String, dynamic>>[];
        for (final row in moved) {
          if (row.containsKey('heading')) {
            department = row['heading'] as String;
          } else if (row.containsKey('id')) {
            items.add({...row, 'department': department});
          }
        }
        _save(items);
      },
      itemBuilder: (context, index) {
        final item = rows[index];
        if (item.containsKey('empty')) {
          return Container(
            key: ValueKey('empty-${item['empty']}'),
            height: 48,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .5),
              ),
            ),
          );
        }
        if (item.containsKey('heading')) {
          final department = item['heading'] as String;
          return Padding(
            key: ValueKey('department-$department'),
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
            child: Semantics(
              header: true,
              child: Text(
                department,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }
        final checked = item['checked'] == true;
        return ReorderableDelayedDragStartListener(
          key: ValueKey(item['id']),
          index: index,
          enabled: !_loading,
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.only(left: 4, right: 16),
              leading: Checkbox(
                value: checked,
                onChanged: busy
                    ? null
                    : (value) => _save([
                        for (final i in _items)
                          i['id'] == item['id'] ? {...i, 'checked': value} : i,
                      ]),
              ),
              title: Text(
                item['name'] as String,
                style: TextStyle(
                  decoration: checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  color: checked ? colors.onSurfaceVariant : colors.onSurface,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = _loading || _saving;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping list'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  widget.householdName,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: colors.primary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final field = TextField(
                              controller: _name,
                              focusNode: _focus,
                              enabled: !busy,
                              maxLength: 200,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                hintText: 'Add an item',
                                counterText: '',
                              ),
                              onSubmitted: (_) => _add(),
                            );
                            final add = FilledButton.icon(
                              onPressed: busy || _items.length >= 500
                                  ? null
                                  : _add,
                              icon: const Icon(Icons.add),
                              label: const Text('Add item'),
                            );
                            if (constraints.maxWidth < 400 ||
                                MediaQuery.textScalerOf(context).scale(1) >
                                    1.4) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  field,
                                  const SizedBox(height: 12),
                                  add,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: field),
                                const SizedBox(width: 12),
                                add,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _department,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          items: shoppingDepartments
                              .map(
                                (d) =>
                                    DropdownMenuItem(value: d, child: Text(d)),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) => setState(() => _department = value!),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _shoppingList(busy),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: OutlinedButton.icon(
                    onPressed: busy || !_items.any((i) => i['checked'] == true)
                        ? null
                        : () => _save(
                            _items.where((i) => i['checked'] != true).toList(),
                          ),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Remove checked off'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
