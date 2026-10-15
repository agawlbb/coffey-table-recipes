import 'package:flutter/material.dart';

import 'administration.dart';
import 'api.dart';

class ParentCategories extends StatefulWidget {
  const ParentCategories({super.key, required this.request});
  final AdministrationRequest request;

  @override
  State<ParentCategories> createState() => _ParentCategoriesState();
}

class _ParentCategoriesState extends State<ParentCategories> {
  List<Map<String, dynamic>> _categories = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([Map<String, dynamic>? body]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.request('/admin/parent-categories', body: body);
      if (mounted) {
        setState(
          () => _categories = List<Map<String, dynamic>>.from(
            data['categories'] as List,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Could not reach categories. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? category]) async {
    final controller = TextEditingController(
      text: category?['label'] as String? ?? '',
    );
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          category == null ? 'Add parent category' : 'Rename parent category',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Category name'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, value.text.trim()),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
    // The dialog's closing animation can still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (label != null && mounted) {
      await _load({
        'action': category == null ? 'add' : 'rename',
        if (category != null) 'id': category['id'],
        'label': label,
      });
    }
  }

  Future<void> _delete(Map<String, dynamic> category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete parent category?'),
        content: Text(
          'Delete ${category['label']} from the shared catalog for all households?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _load({'action': 'delete', 'id': category['id']});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Parent categories'),
      actions: [
        IconButton(
          tooltip: 'Refresh categories',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'This catalog is shared across all households. Only parents with no subcategories or recipe assignments (including Recently Deleted) can be deleted.',
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add parent category'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  if (_categories.isEmpty && !_busy && _error == null)
                    const ListTile(title: Text('No parent categories.')),
                  for (final category in _categories)
                    ListTile(
                      title: Text(category['label'] as String),
                      subtitle: Text(
                        category['can_delete'] == true
                            ? 'Empty'
                            : '${category['child_count']} subcategories · ${category['assignment_count']} direct recipe assignments',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename ${category['label']}',
                            onPressed: _busy ? null : () => _edit(category),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: category['can_delete'] == true
                                ? 'Delete ${category['label']}'
                                : 'Only empty parent categories can be deleted',
                            onPressed: _busy || category['can_delete'] != true
                                ? null
                                : () => _delete(category),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
