import 'package:flutter/material.dart';

import 'shopping_ingredient.dart';

class RecipeShoppingSelector extends StatefulWidget {
  const RecipeShoppingSelector({
    super.key,
    required this.ingredients,
    required this.onAdd,
    this.loadExisting,
  });

  final List<ShoppingIngredient> ingredients;
  final Future<void> Function(List<String>) onAdd;
  final Future<List<String>> Function()? loadExisting;

  @override
  State<RecipeShoppingSelector> createState() => _RecipeShoppingSelectorState();
}

class _RecipeShoppingSelectorState extends State<RecipeShoppingSelector> {
  final _selected = <int>{};
  bool _saving = false;
  String? _error;
  List<String> _existing = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final existing = await widget.loadExisting?.call() ?? <String>[];
      if (mounted) {
        setState(() {
          _existing = existing;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not check the shopping list.';
        });
      }
    }
  }

  String? _match(int index) {
    if (!_selected.contains(index)) return null;
    for (final name in _existing) {
      if (similarShoppingIngredients(widget.ingredients[index].name, name)) {
        return name;
      }
    }
    return null;
  }

  Future<void> _add() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onAdd([
        for (var i = 0; i < widget.ingredients.length; i++)
          if (_selected.contains(i)) widget.ingredients[i].name,
      ]);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not add ingredients. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Add to shopping list'),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < widget.ingredients.length; i++)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        color: _selected.contains(i)
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          selected: _selected.contains(i),
                          title: Text(widget.ingredients[i].name),
                          trailing: Icon(
                            _selected.contains(i)
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                          ),
                          onTap: _saving
                              ? null
                              : () => setState(() {
                                  if (!_selected.add(i)) _selected.remove(i);
                                }),
                        ),
                      ),
                    ),
                    if (widget.ingredients[i].details.isNotEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(widget.ingredients[i].details),
                        ),
                      ),
                  ],
                ),
                if (_match(i) case final String match)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: Text(
                      'Already on shopping list: $match',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          if (_error != null) Text(_error!),
          if (_loading && _error == null) const LinearProgressIndicator(),
          if (_loading && _error != null)
            TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _saving || _loading || _selected.isEmpty ? null : _add,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ),
    ),
  );
}
