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
  final _listController = ScrollController();
  final _listKey = GlobalKey();
  Timer? _autoScroll;
  double _scrollStep = 0;
  Offset? _dragPosition;
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
    // Keep the dropped order visible while serializing writes against the
    // server revision.
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
    _autoScroll?.cancel();
    _listController.dispose();
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
    ],
  ];

  void _dragStarted() {
    _dragging = true;
    _dragPosition = null;
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_listController.hasClients || _scrollStep == 0) return;
      final position = _listController.position;
      _listController.jumpTo(
        (_listController.offset + _scrollStep).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _dragUpdated(DragUpdateDetails details) {
    _dragPosition = details.globalPosition;
    final box = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final y = box.globalToLocal(details.globalPosition).dy;
    _scrollStep = y < 48
        ? -12
        : y > box.size.height - 48
        ? 12
        : 0;
  }

  void _dragFinished() {
    _dragging = false;
    _scrollStep = 0;
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragPosition = null;
  }

  void _dropItem(
    String id,
    String department, {
    String? target,
    bool after = false,
  }) {
    final original = _items.where((item) => item['id'] == id).firstOrNull;
    if (original == null || target == id) return;
    final items = _items.where((item) => item['id'] != id).toList();
    final targetIndex = target == null
        ? -1
        : items.indexWhere((item) => item['id'] == target);
    final index = targetIndex >= 0
        ? targetIndex + (after ? 1 : 0)
        : items.lastIndexWhere((item) => item['department'] == department) + 1;
    items.insert(index, {...original, 'department': department});
    if (List.generate(
      items.length,
      (i) =>
          items[i]['id'] == _items[i]['id'] &&
          items[i]['department'] == _items[i]['department'],
    ).every((same) => same)) {
      return;
    }
    _save(items);
  }

  Widget _itemCard(
    Map<String, dynamic> item,
    bool busy, {
    bool highlighted = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final checked = item['checked'] == true;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        color: highlighted ? colors.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: busy
                    ? null
                    : (value) => _save([
                        for (final i in _items)
                          i['id'] == item['id'] ? {...i, 'checked': value} : i,
                      ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['name'] as String,
                  style: TextStyle(
                    decoration: checked
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: checked ? colors.onSurfaceVariant : colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shoppingList(bool busy) {
    final colors = Theme.of(context).colorScheme;
    final rows = _rows;
    final rowIndices = <Key, int>{
      for (var i = 0; i < rows.length; i++)
        ValueKey<String>(
          rows[i].containsKey('heading')
              ? 'department-${rows[i]['heading']}'
              : rows[i]['id'] as String,
        ): i,
    };
    return ListView.builder(
      key: _listKey,
      controller: _listController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: rows.length,
      // Preserve the drag recognizer when an item changes its sliver index.
      findChildIndexCallback: (key) => rowIndices[key],
      itemBuilder: (context, index) {
        final item = rows[index];
        if (item.containsKey('heading')) {
          final department = item['heading'] as String;
          return DragTarget<String>(
            key: ValueKey('department-$department'),
            hitTestBehavior: HitTestBehavior.opaque,
            onWillAcceptWithDetails: (_) => !_loading,
            onAcceptWithDetails: (details) {
              _dragFinished();
              _dropItem(details.data, department);
            },
            builder: (context, candidates, rejected) => Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: candidates.isEmpty ? null : colors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
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
            ),
          );
        }
        return LayoutBuilder(
          key: ValueKey(item['id'] as String),
          builder: (rowContext, constraints) => DragTarget<String>(
            hitTestBehavior: HitTestBehavior.opaque,
            onWillAcceptWithDetails: (details) =>
                !_loading && details.data != item['id'],
            onAcceptWithDetails: (details) {
              final box = rowContext.findRenderObject() as RenderBox;
              final after =
                  box.globalToLocal(_dragPosition ?? details.offset).dy >
                  box.size.height / 2;
              _dragFinished();
              _dropItem(
                details.data,
                item['department'] as String,
                target: item['id'] as String,
                after: after,
              );
            },
            builder: (context, candidates, rejected) =>
                LongPressDraggable<String>(
                  data: item['id'] as String,
                  maxSimultaneousDrags: _loading ? 0 : 1,
                  hitTestBehavior: HitTestBehavior.opaque,
                  onDragStarted: _dragStarted,
                  onDragUpdate: _dragUpdated,
                  // Completion/cancellation also run if the source row is
                  // disposed while dragging; onDragEnd is mounted-only.
                  onDragCompleted: _dragFinished,
                  onDraggableCanceled: (_, _) => _dragFinished(),
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: IgnorePointer(child: _itemCard(item, true)),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: .3,
                    child: _itemCard(item, true),
                  ),
                  child: _itemCard(
                    item,
                    busy,
                    highlighted: candidates.isNotEmpty,
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
