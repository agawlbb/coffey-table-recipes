import 'child_mode.dart';

import 'package:flutter/material.dart';

import 'api.dart';
import 'recipe_menu.dart';
import 'shopping_list.dart';

class ShoppingDepartmentsScreen extends StatefulWidget {
  const ShoppingDepartmentsScreen({
    super.key,
    required this.householdId,
    required this.request,
    this.menuBuilder,
  });
  final String householdId;
  final ShoppingRequest request;
  final WidgetBuilder? menuBuilder;

  @override
  State<ShoppingDepartmentsScreen> createState() =>
      _ShoppingDepartmentsScreenState();
}

class _ShoppingDepartmentsScreenState extends State<ShoppingDepartmentsScreen> {
  List<String> _departments = [];
  List<Map<String, dynamic>> _items = [];
  int _revision = 0;
  bool _busy = true;
  String? _error;
  String get _path => '/households/${widget.householdId}/shopping-list';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _accept(Map<String, dynamic> data) {
    _revision = data['revision'] as int;
    _departments = (data['departments'] as List).cast<String>();
    _items = (data['items'] as List)
        .map((i) => Map<String, dynamic>.from(i as Map))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.request(_path);
      if (mounted) setState(() => _accept(data));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load departments.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(
    List<String> departments,
    List<Map<String, dynamic>> items, {
    Map<String, String>? renames,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.request(
        _path,
        body: {
          'revision': _revision,
          'departments': departments,
          'items': items,
          'department_renames': ?renames,
        },
      );
      if (mounted) setState(() => _accept(data));
    } catch (error) {
      if (error is ApiException && error.status == 409) {
        await _load();
      }
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Could not save departments.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([String? old]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _DepartmentNameDialog(old: old, departments: _departments),
    );
    if (name == null || !mounted || name == old) return;
    final departments = [..._departments];
    if (old == null) {
      departments.add(name);
    } else {
      departments[departments.indexOf(old)] = name;
    }
    await _save(departments, [
      for (final item in _items)
        {...item, if (item['department'] == old) 'department': name},
    ], renames: old == null ? null : {old: name});
  }

  Future<void> _remove(String department) async {
    final occupied = _items.any((i) => i['department'] == department);
    if (occupied) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove $department?'),
          content: const Text('Its items will move above the departments.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (remove != true || !mounted) return;
    }
    await _save(_departments.where((d) => d != department).toList(), [
      for (final item in _items)
        {...item, if (item['department'] == department) 'department': ''},
    ]);
  }

  @override
  Widget build(BuildContext context) => childModeOf(context)
      ? const Scaffold(
          body: SafeArea(
            child: Center(child: Text('Unavailable in child mode.')),
          ),
        )
      : _buildAdultScreen(context);

  Widget _buildAdultScreen(BuildContext context) => Scaffold(
    drawer: widget.menuBuilder?.call(context),
    appBar: AppBar(
      title: const Text('Shopping list departments'),
      leadingWidth: widget.menuBuilder == null ? null : 96,
      leading: widget.menuBuilder == null ? null : const RecipeMenuLeading(),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Retry'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _busy || _departments.length >= 50
                    ? null
                    : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add department'),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                buildDefaultDragHandles: false,
                itemCount: _departments.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (_busy) return;
                  final departments = [..._departments];
                  departments.insert(newIndex, departments.removeAt(oldIndex));
                  _save(departments, _items);
                },
                itemBuilder: (context, index) {
                  final department = _departments[index];
                  return Card(
                    key: ValueKey(department),
                    child: ListTile(
                      leading: ReorderableDragStartListener(
                        index: index,
                        enabled: !_busy,
                        child: const ColoredBox(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ),
                      title: Text(department),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename $department',
                            onPressed: _busy ? null : () => _edit(department),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Remove $department',
                            onPressed: _busy ? null : () => _remove(department),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DepartmentNameDialog extends StatefulWidget {
  const _DepartmentNameDialog({required this.old, required this.departments});
  final String? old;
  final List<String> departments;
  @override
  State<_DepartmentNameDialog> createState() => _DepartmentNameDialogState();
}

class _DepartmentNameDialogState extends State<_DepartmentNameDialog> {
  late final _controller = TextEditingController(text: widget.old ?? '');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.old == null ? 'Add department' : 'Rename department'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Department name'),
        validator: (value) {
          final name = value?.trim() ?? '';
          if (name.isEmpty) {
            return 'Enter a department name';
          }
          if (widget.departments.any(
            (d) => d != widget.old && d.toLowerCase() == name.toLowerCase(),
          )) {
            return 'Department already exists';
          }
          return null;
        },
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
