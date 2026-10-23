import 'child_mode.dart';

import 'package:flutter/material.dart';

import 'shopping_ingredient.dart';

class RecipeShoppingSelector extends StatefulWidget {
  const RecipeShoppingSelector({
    super.key,
    required this.ingredients,
    required this.onAdd,
    this.loadExisting,
    this.onChooseDates,
    this.blankRecipeTitles,
  });

  final List<ShoppingIngredient> ingredients;
  final List<String> Function()? blankRecipeTitles;
  final Future<List<ShoppingIngredient>?> Function(BuildContext)? onChooseDates;
  final Future<void> Function(List<String>) onAdd;
  final Future<List<String>> Function()? loadExisting;

  @override
  State<RecipeShoppingSelector> createState() => _RecipeShoppingSelectorState();
}

class _RecipeShoppingSelectorState extends State<RecipeShoppingSelector> {
  final _selected = <int>{};
  bool _saving = false;
  bool _changingDates = false;
  late List<ShoppingIngredient> _ingredients;
  String? _error;
  List<String> _existing = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ingredients = widget.ingredients;
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

  Future<void> _chooseDates() async {
    setState(() => _changingDates = true);
    try {
      final ingredients = await widget.onChooseDates!(context);
      if (mounted && ingredients != null) {
        setState(() {
          _ingredients = ingredients;
          _selected.clear();
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load meal ingredients. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _changingDates = false);
    }
  }

  String? _match(int index) {
    if (!_selected.contains(index)) return null;
    for (final name in _existing) {
      if (similarShoppingIngredients(_ingredients[index].name, name)) {
        return name;
      }
    }
    return null;
  }

  Future<void> _add() async {
    if (childMode.value) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onAdd([
        for (var i = 0; i < _ingredients.length; i++)
          if (_selected.contains(i)) _ingredients[i].name,
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
        title: Row(
          children: [
            Flexible(child: Text('Add to shopping list')),
            if (widget.onChooseDates != null)
              IconButton(
                tooltip: 'Choose meal dates',
                onPressed: childMode.value || _saving || _changingDates
                    ? null
                    : _chooseDates,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
          ],
        ),
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
          if (widget.blankRecipeTitles?.call().isNotEmpty ?? false)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Blank recipes are included. Ingredients they require are not shown in this list.',
                    ),
                    for (final title in widget.blankRecipeTitles!())
                      Text(title),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < _ingredients.length; i++)
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
                          title: Text(_ingredients[i].name),
                          trailing: Icon(
                            _selected.contains(i)
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                          ),
                          onTap: childMode.value || _saving || _changingDates
                              ? null
                              : () => setState(() {
                                  if (!_selected.add(i)) _selected.remove(i);
                                }),
                        ),
                      ),
                    ),
                    if (_ingredients[i].details.isNotEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(_ingredients[i].details),
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
          if (_ingredients.isEmpty && !_changingDates)
            const Text('No ingredients for these dates.'),
          if (_changingDates) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (_loading && _error == null) const LinearProgressIndicator(),
          if (_loading && _error != null)
            TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed:
              childModeOf(context) ||
                  _saving ||
                  _changingDates ||
                  _loading ||
                  _selected.isEmpty
              ? null
              : _add,
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
