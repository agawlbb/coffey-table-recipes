import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'api.dart';
import 'shopping_item_id.dart';
import 'shopping_list_cache.dart';

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
    this.embedded = false,
    this.active = true,
    this.cache,
  });
  final String householdId;
  final String householdName;
  final ShoppingRequest request;
  final bool embedded;
  final bool active;
  final ShoppingListCache? cache;

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
  bool _hideEmptyDepartments = false;
  List<String> _departments = [
    ...shoppingDepartments.where((d) => d != 'Other'),
    'Other',
  ];
  int _revision = 0;
  int _saveGeneration = 0;
  bool _loading = true, _saving = false, _reading = false;
  bool _dragging = false;
  bool _routeVisible = false;
  bool _disconnected = false, _accessDenied = false, _serverLoaded = false;
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
    _restoreCache();
    if (widget.active) _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.active &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          _routeVisible) {
        _load();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    final opening = visible && !_routeVisible;
    _routeVisible = visible;
    if (opening && widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant ShoppingListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _routeVisible) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.active && _routeVisible && state == AppLifecycleState.resumed) {
      _load();
    }
  }

  void _accept(Map<String, dynamic> data) {
    _departments =
        (data['departments'] as List?)?.cast<String>() ?? _departments;
    _revision = data['revision'] as int;
    _items = (data['items'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    _confirmedItems = _items;
  }

  Future<void> _restoreCache() async {
    final data = await widget.cache?.read();
    if (data != null &&
        mounted &&
        !_serverLoaded &&
        !_saving &&
        !_accessDenied) {
      setState(() {
        _accept(data);
        _loading = false;
      });
    }
  }

  void _cacheConfirmed() {
    unawaited(
      widget.cache?.save({
        'revision': _revision,
        'items': _confirmedItems,
        'departments': _departments,
      }),
    );
  }

  bool _connectionFailure(Object error) =>
      error is! ApiException || error.status >= 500 || error.status == 408;

  Future<void> _load() async {
    if (_saving || _reading || _dragging) return;
    _reading = true;
    final generation = _saveGeneration;
    try {
      final data = await widget.request(_path);
      if (!mounted) return;
      final firstResponse = !_serverLoaded;
      _serverLoaded = true;
      if (!_saving && !_dragging && generation == _saveGeneration) {
        final changed =
            firstResponse || _loading || data['revision'] != _revision;
        if (changed || _disconnected || _accessDenied || _error != null) {
          setState(() {
            if (changed) _accept(data);
            _disconnected = false;
            _accessDenied = false;
            _error = null;
          });
        }
        if (changed) _cacheConfirmed();
      }
    } catch (error) {
      if (!mounted) return;
      if (_connectionFailure(error)) {
        if (!_disconnected) setState(() => _disconnected = true);
      } else {
        final denied =
            error is ApiException && [401, 403, 404].contains(error.status);
        if (denied) unawaited(widget.cache?.clear());
        setState(() {
          _disconnected = false;
          if (denied) {
            _accessDenied = true;
            _items = [];
            _confirmedItems = [];
            _revision = 0;
          }
          _error = (error as ApiException).message;
        });
      }
    } finally {
      _reading = false;
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<bool> _save(List<Map<String, dynamic>> items) {
    if (_disconnected || _accessDenied) return Future.value(false);
    _saveGeneration++;
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
        _departments =
            (data['departments'] as List?)?.cast<String>() ?? _departments;
        _revision = data['revision'] as int;
        _confirmedItems = (data['items'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _serverLoaded = true;
        _disconnected = false;
        _accessDenied = false;
        _cacheConfirmed();
        // Carry server-selected departments into queued snapshots, unless a
        // later drag explicitly chose a different department for that item.
        final sent = {for (final item in write.items) item['id']: item};
        for (final confirmed in _confirmedItems) {
          final original = sent[confirmed['id']];
          if (original == null ||
              original['department'] == confirmed['department']) {
            continue;
          }
          for (final pending in _writes.skip(1)) {
            for (var i = 0; i < pending.items.length; i++) {
              final item = pending.items[i];
              if (item['id'] == confirmed['id'] &&
                  item['department'] == original['department']) {
                pending.items[i] = {
                  ...item,
                  'department': confirmed['department'],
                };
              }
            }
          }
        }
        _writes.removeAt(0);
        if (!write.done.isCompleted) write.done.complete(true);
      } catch (error) {
        if (error is ApiException && error.status == 409) {
          try {
            final data = await widget.request(_path);
            _departments =
                (data['departments'] as List?)?.cast<String>() ?? _departments;
            _revision = data['revision'] as int;
            _confirmedItems = (data['items'] as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
            _cacheConfirmed();
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
            if (_connectionFailure(error)) _disconnected = true;
            if (error is ApiException &&
                [401, 403, 404].contains(error.status)) {
              _accessDenied = true;
              _items = [];
              _confirmedItems = [];
              _revision = 0;
              unawaited(widget.cache?.clear());
            }
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
    if (mounted) {
      setState(() {
        _items = _confirmedItems;
        _saving = false;
      });
    }
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
        'department': '',
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
    {'heading': ''},
    ..._items.where((item) => item['department'] == ''),
    for (final department in _departments)
      if (!_hideEmptyDepartments ||
          _items.any((item) => item['department'] == department)) ...[
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
    if (original == null || target == id || _disconnected || _accessDenied) {
      return;
    }
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
            onWillAcceptWithDetails: (_) =>
                !_loading && !_disconnected && !_accessDenied,
            onAcceptWithDetails: (details) {
              _dragFinished();
              _dropItem(details.data, department);
            },
            builder: (context, candidates, rejected) => Container(
              height: department.isEmpty ? 16 : 30,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: candidates.isEmpty ? null : colors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Semantics(
                header: department.isNotEmpty,
                label: department.isEmpty ? 'No department' : null,
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
                !_loading &&
                !_disconnected &&
                !_accessDenied &&
                details.data != item['id'],
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
            builder: (context, candidates, rejected) {
              final feedback = Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: IgnorePointer(child: _itemCard(item, true)),
                ),
              );
              final placeholder = Opacity(
                opacity: .3,
                child: _itemCard(item, true),
              );
              Widget source(bool touch, Widget child) => _ShoppingDragSource(
                touch: touch,
                data: item['id'] as String,
                maxSimultaneousDrags: _loading || _disconnected || _accessDenied
                    ? 0
                    : 1,
                onDragStarted: _dragStarted,
                onDragUpdate: _dragUpdated,
                onDragCompleted: _dragFinished,
                onDraggableCanceled: (_, _) => _dragFinished(),
                feedback: feedback,
                childWhenDragging: placeholder,
                child: child,
              );
              return source(
                false,
                source(
                  true,
                  _itemCard(item, busy, highlighted: candidates.isNotEmpty),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = _loading || _saving || _disconnected || _accessDenied;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Shopping list'),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading || _saving ? null : () => _load(),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.householdName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: colors.primary),
                      ),
                    ),
                    if (_disconnected)
                      Tooltip(
                        message: 'No server connection',
                        child: Semantics(
                          liveRegion: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Offline',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _name,
                            focusNode: _focus,
                            enabled: !_loading && !_saving,
                            maxLength: 200,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              hintText: 'Add an item',
                              counterText: '',
                            ),
                            onSubmitted: (_) => _add(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Add item',
                          onPressed: busy || _items.length >= 500 ? null : _add,
                          icon: const Icon(Icons.add),
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
                        onPressed: _loading || _saving ? null : () => _load(),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        title: const Text('Hide empty departments'),
                        value: _hideEmptyDepartments,
                        onChanged: (value) =>
                            setState(() => _hideEmptyDepartments = value!),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            busy || !_items.any((i) => i['checked'] == true)
                            ? null
                            : () => _save(
                                _items
                                    .where((i) => i['checked'] != true)
                                    .toList(),
                              ),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Remove checked off'),
                      ),
                    ],
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

// Mouse gestures should use normal click-and-drag; touch retains a long press
// so a normal swipe can still scroll. Each recognizer filters its own devices.
class _ShoppingDragSource extends Draggable<String> {
  const _ShoppingDragSource({
    required this.touch,
    required super.data,
    required super.child,
    required super.feedback,
    required super.childWhenDragging,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragCompleted,
    super.onDraggableCanceled,
  }) : super(hitTestBehavior: HitTestBehavior.opaque);

  final bool touch;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    final MultiDragGestureRecognizer recognizer = touch
        ? DelayedMultiDragGestureRecognizer(
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
          )
        : ImmediateMultiDragGestureRecognizer(
            supportedDevices: const {PointerDeviceKind.mouse},
          );
    return recognizer..onStart = onStart;
  }
}
