import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_recipes.dart';
import 'recipe_browser.dart';
import 'recipe_editor.dart';

class RecipeTrash extends StatefulWidget {
  const RecipeTrash({
    super.key,
    required this.householdId,
    required this.request,
    required this.save,
  });
  final String householdId;
  final RecipeRequest request;
  final RecipeSave save;

  @override
  State<RecipeTrash> createState() => _RecipeTrashState();
}

class _RecipeTrashState extends State<RecipeTrash> {
  final List<Map<String, dynamic>> _recipes = [];
  bool _busy = true;
  String? _restoring;
  String? _error;
  int? _next;
  String get _root => '/households/${widget.householdId}/recipes';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (offlineStatus.value) {
        throw ApiException(
          0,
          'Connect to the internet to view Recently Deleted.',
        );
      }
      final data = await widget.request(
        '$_root/deleted?offset=${more ? _next ?? 0 : 0}',
      );
      if (!mounted) return;
      setState(() {
        if (!more) _recipes.clear();
        _recipes.addAll(recipeRows(data['recipes']));
        _next = data['next_offset'] as int?;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException ? error.message : 'Could not load Recently Deleted. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> recipe) async {
    final id = '${recipe['id']}';
    setState(() => _restoring = id);
    try {
      if (offlineStatus.value) {
        throw ApiException(0, 'Connect to the internet to restore a recipe.');
      }
      await widget.save('$_root/$id/restore', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${recipe['title']} restored')));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException ? error.message : 'Could not restore recipe. Check your connection and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = null);
    }
  }

  String _dates(Map<String, dynamic> recipe) {
    final deleted = DateTime.parse('${recipe['deleted_at']}').toLocal();
    final expiry = DateTime.parse('${recipe['purge_after']}').toLocal();
    final days = (expiry.difference(DateTime.now()).inSeconds / 86400)
        .ceil()
        .clamp(0, 30);
    return 'Deleted ${deleted.month}/${deleted.day}/${deleted.year} · ${days == 0 ? 'Expires today' : '$days ${days == 1 ? 'day' : 'days'} left'}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Recently Deleted'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _busy || _restoring != null ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Deleted recipes can be restored for 30 days. After that, they are permanently removed.',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _busy ? null : () => _load(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (!_busy && _error == null && _recipes.isEmpty)
              const Expanded(
                child: Center(child: Text('No recently deleted recipes.')),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    for (final recipe in _recipes)
                      ListTile(
                        title: Text('${recipe['title']}'),
                        subtitle: Text(_dates(recipe)),
                        trailing: TextButton(
                          onPressed: _busy || _restoring != null
                              ? null
                              : () => _restore(recipe),
                          child: Text(
                            _restoring == '${recipe['id']}'
                                ? 'Restoring…'
                                : 'Restore',
                          ),
                        ),
                      ),
                    if (_next != null)
                      TextButton(
                        onPressed: _busy || _restoring != null
                            ? null
                            : () => _load(more: true),
                        child: const Text('Load more'),
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
