import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'cooking_mode.dart';

typedef RecipeRequest = Future<Map<String, dynamic>> Function(String path);

String recipeValue(Object? value) {
  if (value == null) return '';
  return value
      .toString()
      .replaceFirstMapped(RegExp(r'(\.\d*?[1-9])0+$'), (match) => match[1]!)
      .replaceFirst(RegExp(r'\.0+$'), '');
}

List<Map<String, dynamic>> recipeRows(Object? value) =>
    List<Map<String, dynamic>>.from(value as List? ?? []);

String recipeSummary(Map<String, dynamic> recipe) {
  final parts = <String>[];
  if (recipe['total_minutes'] != null) {
    parts.add('${recipe['total_minutes']} min total');
  } else {
    if (recipe['prep_minutes'] != null) {
      parts.add('${recipe['prep_minutes']} min prep');
    }
    if (recipe['cook_minutes'] != null) {
      parts.add('${recipe['cook_minutes']} min cook');
    }
  }
  if (recipe['yield_text'] != null) {
    parts.add(recipe['yield_text'] as String);
  } else if (recipe['servings'] != null) {
    parts.add('${recipeValue(recipe['servings'])} servings');
  }
  return parts.join(' · ');
}

class RecipeBrowser extends StatefulWidget {
  const RecipeBrowser({
    super.key,
    required this.householdId,
    required this.householdName,
    required this.request,
    this.embedded = false,
  });
  final String householdId;
  final String householdName;
  final RecipeRequest request;
  final bool embedded;
  @override
  State<RecipeBrowser> createState() => _RecipeBrowserState();
}

class _RecipeBrowserState extends State<RecipeBrowser> {
  final _search = TextEditingController();
  final List<Map<String, dynamic>> _recipes = [];
  int? _next;
  int _generation = 0;
  String _query = '';
  final List<Map<String, dynamic>> _trail = [];
  List<Map<String, dynamic>> _nodes = [];
  bool _categoryView = true;
  String get _scopeLabel =>
      _trail.isEmpty ? 'All recipes' : _trail.last['label'] as String;
  String? _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    if (!more) _query = _search.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _recipes.clear();
        _nodes = [];
        _next = null;
      }
    });
    try {
      final query = Uri(
        queryParameters: {
          'q': _query,
          'offset': '${more ? _next ?? 0 : 0}',
          'tree': '1',
          if (_trail.isNotEmpty) 'scope': '${_trail.last['id']}',
        },
      ).query;
      final data = await widget.request(
        '/households/${widget.householdId}/recipes?$query',
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _recipes.addAll(recipeRows(data['recipes']));
        _next = data['next_offset'] as int?;
        _nodes = recipeRows(data['category_nodes']);
        _categoryView = data['view'] == 'categories';
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error is ApiException
              ? error.message
              : 'Could not load recipes. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _enterCategory(Map<String, dynamic> category) {
    setState(() {
      _trail.add(category);
      _search.clear();
      _next = null;
    });
    _load();
  }

  void _back() {
    setState(() {
      if (_trail.isNotEmpty) _trail.removeLast();
      _search.clear();
      _next = null;
    });
    _load();
  }

  void _open(Map<String, dynamic> recipe) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RecipeDetail(
        householdId: widget.householdId,
        recipeId: recipe['id'] as String,
        title: recipe['title'] as String,
        request: widget.request,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => widget.embedded
      ? _content(context)
      : Scaffold(
          appBar: AppBar(
            title: Text('${widget.householdName} recipes'),
            actions: [
              IconButton(
                onPressed: _busy ? null : () => _load(),
                tooltip: 'Refresh recipes',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: _content(context),
        );

  Widget _content(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _search,
              mouseCursor: kIsWeb
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.text,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _trail.isEmpty
                    ? 'Search all recipes'
                    : 'Search ${_scopeLabel.toLowerCase()}',
                hintText: 'Title, ingredient, cuisine or technique',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_search.text.isNotEmpty || _query.isNotEmpty)
                      IconButton(
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                      ),
                    IconButton(
                      onPressed: () => _load(),
                      tooltip: 'Search recipes',
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _query.isNotEmpty
                    ? 'Results in $_scopeLabel'
                    : _trail.isEmpty
                    ? 'Browse categories'
                    : _trail.map((c) => c['label']).join(' › '),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: () => _load(more: _recipes.isNotEmpty),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (!_busy &&
              _error == null &&
              (_categoryView ? _nodes.isEmpty : _recipes.isEmpty))
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _categoryView
                    ? 'No recipes in this category yet.'
                    : 'No recipes found in this scope. Try another search.',
              ),
            ),
          Expanded(
            child: ListView.builder(
              key: ValueKey(
                '${_trail.isEmpty ? "root" : _trail.last['id']}:$_query',
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: _categoryView
                  ? _nodes.length
                  : _recipes.length + (_next != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (_categoryView) {
                  final category = _nodes[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _busy ? null : () => _enterCategory(category),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: Image.asset(
                                'assets/categories/${category['image_key']}.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, error, stack) =>
                                    const Icon(Icons.restaurant, size: 36),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    category['label'] as String,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${category['recipe_count']} ${category['recipe_count'].toString() == '1' ? 'recipe' : 'recipes'}',
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                if (index == _recipes.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _load(more: true),
                      child: const Text('Load more recipes'),
                    ),
                  );
                }
                final recipe = _recipes[index];
                final summary = recipeSummary(recipe);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(recipe),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: RecipePhoto(
                              url: recipe['photo_url'] as String?,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  recipe['title'] as String,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                if (summary.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(summary),
                                ],
                                if (recipe['description'] != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    recipe['description'] as String,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy || (_trail.isEmpty && _query.isEmpty)
                      ? null
                      : _back,
                  icon: const Icon(Icons.arrow_back),
                  label: Text(
                    _trail.length > 1
                        ? 'Back to ${_trail[_trail.length - 2]['label']}'
                        : 'Back to main categories',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class RecipePhoto extends StatelessWidget {
  const RecipePhoto({super.key, this.url});
  final String? url;
  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url ?? '');
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.restaurant, size: 36)),
    );
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return placeholder;
    }
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, error, stack) => placeholder,
    );
  }
}

class RecipeDetail extends StatefulWidget {
  const RecipeDetail({
    super.key,
    required this.householdId,
    required this.recipeId,
    required this.title,
    required this.request,
  });
  final String householdId;
  final String recipeId;
  final String title;
  final RecipeRequest request;
  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends State<RecipeDetail> {
  Map<String, dynamic>? _recipe;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final data = await widget.request(
        '/households/${widget.householdId}/recipes/${widget.recipeId}',
      );
      if (mounted) {
        setState(() {
          _recipe = data['recipe'] as Map<String, dynamic>;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException
              ? error.message
              : 'Could not load this recipe. Check your connection and retry.';
        });
      }
    }
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
  void _openRelated(Map<String, dynamic> row) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RecipeDetail(
        householdId: widget.householdId,
        recipeId: row['id'] as String,
        title: row['title'] as String,
        request: widget.request,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to recipes'),
        ),
      ),
    ),
    body: _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        : _recipe == null
        ? const Center(child: CircularProgressIndicator())
        : _content(_recipe!),
  );

  Widget _content(Map<String, dynamic> recipe) {
    final ingredients = recipeRows(recipe['ingredients']);
    final groups = recipeRows(recipe['groups']);
    final steps = recipeRows(recipe['steps']);
    final actions = recipeRows(recipe['actions']);
    final photos = recipeRows(recipe['photos'])
      ..sort((a, b) => (b['is_cover'] as num).compareTo(a['is_cover'] as num));
    final nutrition = recipe['nutrition'] as Map<String, dynamic>?;
    final summary = recipeSummary(recipe);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              recipe['title'] as String,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: steps.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CookingMode(recipe: recipe),
                      ),
                    ),
              icon: const Icon(Icons.soup_kitchen_outlined),
              label: const Text('Start cooking'),
            ),
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(summary),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Original language: ${recipe['original_language']} · Original measurements',
              ),
            ),
            if (recipe['description'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(recipe['description'] as String),
              ),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 260,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return SizedBox(
                      width: 300,
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: RecipePhoto(
                                url: photo['source_url'] as String?,
                              ),
                            ),
                          ),
                          if (photo['caption'] != null)
                            Text(photo['caption'] as String),
                          if (photo['attribution'] != null)
                            Text(
                              photo['attribution'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            Wrap(
              spacing: 8,
              children: [
                for (final tag in recipeRows(recipe['tags']))
                  Chip(label: Text('${tag['label']}')),
              ],
            ),
            _heading('Ingredients'),
            if (ingredients.isEmpty) const Text('No ingredients recorded.'),
            for (final groupId in <String?>[
              null,
              ...groups.map((g) => g['id'] as String),
            ]) ...[
              if (groupId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    groups.firstWhere((g) => g['id'] == groupId)['title']
                        as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              for (final ingredient in ingredients.where(
                (i) => i['group_id'] == groupId,
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '• ${ingredient['original_text']}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
            ],
            _heading('Method'),
            if (steps.isEmpty) const Text('No cooking steps recorded.'),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (step['section_title'] != null)
                      Text(
                        step['section_title'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    Text(
                      '${step['position']}. ${step['instruction']}',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(height: 1.6),
                    ),
                    for (final action in actions.where(
                      (a) => a['step_id'] == step['id'],
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Chip(
                          avatar: Icon(
                            action['temperature_value'] != null
                                ? Icons.thermostat
                                : Icons.timer_outlined,
                          ),
                          label: Text(
                            [
                              if (action['label'] != null) '${action['label']}',
                              if (action['duration_seconds'] != null)
                                '${action['duration_seconds']} seconds',
                              if (action['temperature_value'] != null)
                                '${recipeValue(action['temperature_value'])}°${action['temperature_unit']}',
                              if (action['label'] == null &&
                                  action['duration_seconds'] == null &&
                                  action['temperature_value'] == null)
                                '${action['action_type']}',
                            ].join(' · '),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (recipe['notes'] != null) ...[
              _heading('Notes'),
              Text(recipe['notes'] as String),
            ],
            if (nutrition != null) ...[
              _heading('Nutrition'),
              Text(
                '${nutrition['is_estimate'] == 1 ? 'Estimated' : 'Reported'} · ${nutrition['basis'] == 'per_serving' ? 'Per serving' : 'Whole recipe'}',
              ),
              if (nutrition['stale'] == true)
                Text(
                  'This estimate needs recalculation after recipe changes.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    'calories_kcal': 'Calories (kcal)',
                    'protein_g': 'Protein (g)',
                    'carbohydrate_g': 'Carbohydrates (g)',
                    'fat_g': 'Fat (g)',
                    'saturated_fat_g': 'Saturated fat (g)',
                    'fiber_g': 'Fiber (g)',
                    'sugar_g': 'Sugar (g)',
                    'sodium_mg': 'Sodium (mg)',
                  }.entries)
                    if (nutrition[entry.key] != null)
                      Text(
                        '${entry.value}: ${recipeValue(nutrition[entry.key])}',
                      ),
                ],
              ),
              Text('Method: ${nutrition['method']}'),
            ],
            if (recipeRows(recipe['related']).isNotEmpty) ...[
              _heading('Recipe family'),
              for (final row in recipeRows(recipe['related']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(row['title'] as String),
                  subtitle: Text(
                    row['id'] == recipe['parent_recipe_id']
                        ? 'Parent recipe'
                        : 'Variation',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openRelated(row),
                ),
            ],
            if (recipeRows(recipe['pairings']).isNotEmpty) ...[
              _heading('Serve alongside'),
              for (final row in recipeRows(recipe['pairings']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(row['title'] as String),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openRelated(row),
                ),
            ],
            if ([
              'source_title',
              'source_author',
              'source_url',
              'source_reference',
            ].any((key) => recipe[key] != null)) ...[
              _heading('Source'),
              for (final key in [
                'source_title',
                'source_author',
                'source_url',
                'source_reference',
              ])
                if (recipe[key] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(recipe[key] as String),
                  ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
