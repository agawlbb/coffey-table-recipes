import 'package:flutter/material.dart';

import 'recipe_browser.dart';
import 'local_data.dart';
import 'recipe_editor.dart';
import 'shopping_item_id.dart';

class RestaurantManager extends StatefulWidget {
  const RestaurantManager({
    super.key,
    required this.householdId,
    required this.request,
    required this.save,
  });
  final String householdId;
  final RecipeRequest request;
  final RecipeSave save;
  @override
  State<RestaurantManager> createState() => _RestaurantManagerState();
}

class _RestaurantManagerState extends State<RestaurantManager> {
  List<Map<String, dynamic>> _items = [];
  final _controllers = <TextEditingController>[];
  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    localDataChanges.removeListener(_localChanged);
    super.dispose();
  }

  int _revision = 0;
  bool _loading = true, _saving = false, _editing = false;
  String? _error;
  String get _path => '/households/${widget.householdId}/restaurants';
  @override
  void initState() {
    super.initState();
    localDataChanges.addListener(_localChanged);
    _load();
  }

  void _localChanged() {
    if (mounted &&
        !_saving &&
        !_editing &&
        localDataChanges.value.startsWith(
          '/households/${widget.householdId}/',
        )) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await widget.request(_path);
      if (mounted) {
        setState(() {
          _items = recipeRows(data['items']);
          _revision = (data['revision'] as num).toInt();
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load restaurants.';
        });
      }
    }
  }

  Future<void> _commit(List<Map<String, dynamic>> items) async {
    setState(() => _saving = true);
    try {
      final data = await widget.save(_path, {
        'revision': _revision,
        'items': items,
      });
      if (mounted) {
        setState(() {
          _items = items;
          _revision = (data['revision'] as num).toInt();
          _error = null;
        });
      }
    } catch (_) {
      await _load();
      if (mounted) {
        setState(
          () => _error = 'Could not save restaurants. Review and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit([int? index]) async {
    final controller = TextEditingController(
      text: index == null ? '' : '${_items[index]['name']}',
    );
    _controllers.add(controller);
    _editing = true;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(index == null ? 'Add restaurant' : 'Edit restaurant'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => update(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    _editing = false;
    if (name == null || !mounted) return;
    final items = _items.map((e) => Map<String, dynamic>.from(e)).toList();
    if (index == null) {
      items.add({
        'id': newShoppingItemId(),
        'name': name,
        'logo_reference': null,
      });
    } else {
      items[index]['name'] = name;
    }
    await _commit(items);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage restaurants')),
    body: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _saving ? null : () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Add restaurant'),
          ),
        ),
        if (_loading || _saving) const LinearProgressIndicator(),
        if (_error != null)
          Row(
            children: [
              Expanded(child: Text(_error!)),
              TextButton(
                onPressed: _saving ? null : _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _items.length,
            onReorderItem: (oldIndex, newIndex) {
              if (_saving) return;
              final items = [..._items];
              items.insert(newIndex, items.removeAt(oldIndex));
              _commit(items);
            },
            itemBuilder: (context, index) => ListTile(
              key: ValueKey(_items[index]['id']),
              title: Text('${_items[index]['name']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit restaurant',
                    onPressed: _saving ? null : () => _edit(index),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove restaurant',
                    onPressed: _saving
                        ? null
                        : () => _commit([..._items]..removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    enabled: !_saving,
                    child: const Icon(Icons.drag_handle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
