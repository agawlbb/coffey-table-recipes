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
  }

  Future<void> _load({bool quiet = false}) async {
    if (_saving || _reading || _dragging) return;
    _reading = true;
    final revision = _revision;
    try {
      final data = await widget.request(_path);
      if (mounted && !_saving && !_dragging && revision == _revision) {
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save(List<Map<String, dynamic>> items) async {
    if (_saving) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    var saved = false;
    try {
      final data = await widget.request(
        _path,
        body: {'revision': _revision, 'items': items},
      );
      if (mounted) setState(() => _accept(data));
      saved = true;
    } catch (error) {
      if (error is ApiException && error.status == 409) {
        try {
          final data = await widget.request(_path);
          if (mounted) setState(() => _accept(data));
        } catch (_) {
          /* Keep the last confirmed list when refresh fails. */
        }
      }
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Could not save the shopping list. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    return saved;
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

  Future<void> _edit(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: item['name'] as String);
    var department = item['department'] as String;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Shopping item'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Item'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: department,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: shoppingDepartments
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => department = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, 'save');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = controller.text.trim();
    // Let the closing dialog finish its animation before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || result == null) return;
    await _save(
      _items
          .where((i) => result != 'delete' || i['id'] != item['id'])
          .map(
            (i) => i['id'] == item['id']
                ? {...i, 'name': name, 'department': department}
                : i,
          )
          .toList(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _focus.dispose();
    super.dispose();
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
                    : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shopping_basket_outlined,
                              size: 52,
                              color: colors.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Your list is empty',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        buildDefaultDragHandles: false,
                        itemCount: _items.length,
                        onReorderStart: (_) => _dragging = true,
                        onReorderEnd: (_) => _dragging = false,
                        onReorderItem: (oldIndex, newIndex) {
                          if (busy) return;
                          final items = [..._items];
                          items.insert(newIndex, items.removeAt(oldIndex));
                          _save(items);
                        },
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final checked = item['checked'] == true;
                          return ReorderableDelayedDragStartListener(
                            key: ValueKey(item['id']),
                            index: index,
                            enabled: !busy,
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 4,
                                  right: 12,
                                ),
                                leading: Checkbox(
                                  value: checked,
                                  onChanged: busy
                                      ? null
                                      : (value) => _save([
                                          for (final i in _items)
                                            i['id'] == item['id']
                                                ? {...i, 'checked': value}
                                                : i,
                                        ]),
                                ),
                                title: Text(
                                  item['name'] as String,
                                  style: TextStyle(
                                    decoration: checked
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                    color: checked
                                        ? colors.onSurfaceVariant
                                        : colors.onSurface,
                                  ),
                                ),
                                subtitle: item['department'] == 'Other'
                                    ? null
                                    : Text(
                                        item['department'] as String,
                                        style: TextStyle(
                                          color: colors.primary,
                                          fontSize: 12,
                                        ),
                                      ),
                                onTap: busy ? null : () => _edit(item),
                                trailing: Icon(
                                  Icons.drag_handle,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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
