import 'package:flutter/material.dart';

class RecipeShoppingSelector extends StatefulWidget {
  const RecipeShoppingSelector({
    super.key,
    required this.ingredients,
    required this.onAdd,
  });

  final List<String> ingredients;
  final Future<void> Function(List<String>) onAdd;

  @override
  State<RecipeShoppingSelector> createState() => _RecipeShoppingSelectorState();
}

class _RecipeShoppingSelectorState extends State<RecipeShoppingSelector> {
  final _selected = <int>{};
  bool _saving = false;
  String? _error;

  Future<void> _add() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onAdd([
        for (var i = 0; i < widget.ingredients.length; i++)
          if (_selected.contains(i)) widget.ingredients[i],
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
      appBar: AppBar(title: const Text('Add to shopping list')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < widget.ingredients.length; i++)
            Card(
              clipBehavior: Clip.antiAlias,
              color: _selected.contains(i)
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                selected: _selected.contains(i),
                title: Text(widget.ingredients[i]),
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
          if (_error != null) Text(_error!),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _saving || _selected.isEmpty ? null : _add,
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
