import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'api.dart';
import 'cooking_mode.dart';
import 'offline_recipes.dart';
import 'recipe_sharing.dart';
import 'recipe_editor.dart';

final recipePhotoCache = CacheManager(
  Config(
    'recentRecipePhotos',
    maxNrOfCacheObjects: 100,
    stalePeriod: const Duration(days: 90),
  ),
);

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

String recipeSourceLabel(Object? source) => switch (source) {
  'ai_text' => 'Pasted text',
  'ai_website' => 'Website link',
  'ai_file' => 'Uploaded file',
  'ai_camera' => 'Camera photo',
  'ai_reviewed' => 'Imported recipe',
  _ => source?.toString() ?? '',
};

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
    this.save,
  });
  final String householdId;
  final String householdName;
  final RecipeRequest request;
  final RecipeSave? save;
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
  String get _scopeLabel =>
      _trail.isEmpty ? 'All recipes' : _trail.last['label'] as String;
  String? _error;
  bool _busy = true;
  bool _wasOffline = false;
  @override
  void initState() {
    super.initState();
    _wasOffline = offlineStatus.value;
    if (mobileOfflineEnabled) offlineStatus.addListener(_connectionChanged);
    _load();
  }

  @override
  void dispose() {
    offlineStatus.removeListener(_connectionChanged);
    _search.dispose();
    super.dispose();
  }

  void _connectionChanged() {
    final recovered = _wasOffline && !offlineStatus.value;
    _wasOffline = offlineStatus.value;
    if (recovered && mounted) _load();
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
          'tree': more ? '0' : '1',
          if (_trail.isNotEmpty) 'scope': '${_trail.last['id']}',
        },
      ).query;
      var data = await widget.request(
        '/households/${widget.householdId}/recipes?$query',
      );
      if (!mounted || generation != _generation) return;
      final nodes = recipeRows(data['category_nodes']);
      for (final category in nodes.where(
        (node) => node['needs_ai_image'] == true,
      )) {
        if (widget.save == null) break;
        try {
          final image = await widget.save!(
            '/households/${widget.householdId}/category-image',
            {'category_id': category['id'].toString()},
          );
          category['image_url'] = image['image_url'];
        } catch (_) {
          // Keep browsing available; a later visit can retry a failed generation.
        }
      }

      if (!more && data['view'] == 'categories') {
        final recipeQuery = Uri(
          queryParameters: {...Uri.splitQueryString(query), 'tree': '0'},
        ).query;
        data = await widget.request(
          '/households/${widget.householdId}/recipes?$recipeQuery',
        );
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _recipes.addAll(recipeRows(data['recipes']));
        _next = data['next_offset'] as int?;
        if (!more) _nodes = nodes;
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
    _returnToLevel(_trail.isEmpty ? 0 : _trail.length - 1);
  }

  void _returnToLevel(int depth) {
    setState(() {
      _trail.removeRange(depth, _trail.length);
      _search.clear();
      _next = null;
    });
    _load();
  }

  Future<void> _open(Map<String, dynamic> recipe) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetail(
          householdId: widget.householdId,
          recipeId: recipe['id'] as String,
          title: recipe['title'] as String,
          request: widget.request,
          save: widget.save,
        ),
      ),
    );
    if (mounted) _load();
  }

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
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_trail.isNotEmpty || _query.isNotEmpty)
                    IconButton(
                      onPressed: _busy ? null : _back,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back one level',
                    ),
                  for (var depth = 0; depth <= _trail.length; depth++) ...[
                    if (depth > 0) const Icon(Icons.chevron_right, size: 18),
                    TextButton(
                      key: ValueKey('recipe-breadcrumb-$depth'),
                      onPressed: _busy ? null : () => _returnToLevel(depth),
                      child: Text(
                        depth == 0
                            ? 'All Recipes'
                            : _trail[depth - 1]['label'] as String,
                        style: TextStyle(
                          fontWeight: depth == _trail.length
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ],
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
          if (!_busy && _error == null && _nodes.isEmpty && _recipes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No recipes found in this scope. Try another search.',
              ),
            ),
          Expanded(
            child: ListView.builder(
              key: ValueKey(
                '${_trail.isEmpty ? "root" : _trail.last['id']}:$_query',
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount:
                  _nodes.length + 1 + _recipes.length + (_next != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _nodes.length) {
                  final category = _nodes[index];
                  return Card(
                    color: const Color(0xffdce5d3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Color(0xff91a580)),
                    ),
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
                              child: category['image_url'] != null
                                  ? RecipePhoto(
                                      url: category['image_url'] as String,
                                    )
                                  : category['needs_ai_image'] == true
                                  ? const Icon(Icons.restaurant, size: 36)
                                  : Image.asset(
                                      'assets/categories/${category['image_key']}.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, error, stack) =>
                                          const Icon(
                                            Icons.restaurant,
                                            size: 36,
                                          ),
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
                final recipeIndex = index - _nodes.length - 1;
                if (recipeIndex == -1) {
                  return Padding(
                    key: const ValueKey('scope-recipes-divider'),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: Color(0xff91a580), thickness: 2),
                        const SizedBox(height: 12),
                        Text(
                          _trail.isEmpty
                              ? 'All recipes'
                              : 'Recipes in $_scopeLabel',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  );
                }
                if (recipeIndex == _recipes.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _load(more: true),
                      child: const Text('Load more recipes'),
                    ),
                  );
                }
                final recipe = _recipes[recipeIndex];
                final summary = recipeSummary(recipe);
                return Card(
                  color: const Color(0xfffff9ee),
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
        ],
      ),
    ),
  );
}

class RecipePhoto extends StatelessWidget {
  const RecipePhoto({super.key, this.url, this.fit = BoxFit.cover});
  final BoxFit fit;
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
    if (mobileOfflineEnabled) {
      return CachedNetworkImage(
        imageUrl: url!,
        cacheManager: recipePhotoCache,
        fit: fit,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }
    return Image.network(
      url!,
      fit: fit,
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
    this.save,
  });
  final String householdId;
  final String recipeId;
  final String title;
  final RecipeRequest request;
  final RecipeSave? save;
  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends State<RecipeDetail> {
  bool _sharing = false;

  Future<void> _shareRecipe(BuildContext anchor) async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.link),
          title: const Text('Send a link'),
          subtitle: const Text('Anyone with the link can view this recipe.'),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (choice != true || !mounted || !anchor.mounted) return;
    final box = anchor.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      final link = recipeShareLink(widget.recipeId);
      var status = ShareResultStatus.unavailable;
      try {
        final result = await SharePlus.instance.share(
          ShareParams(
            text: link,
            subject: widget.title,
            sharePositionOrigin: origin,
          ),
        );
        status = result.status;
      } catch (_) {
        // Keep the link available to copy if platform sharing is unavailable.
      }
      if (status == ShareResultStatus.unavailable && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Recipe link'),
            content: SelectableText(link),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Copy link'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException ? error.message : 'Could not share this recipe. Check your connection and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Map<String, dynamic>? _recipe;
  String? _error;
  bool _wasOffline = false;
  @override
  void initState() {
    super.initState();
    _wasOffline = offlineStatus.value;
    if (mobileOfflineEnabled) offlineStatus.addListener(_connectionChanged);
    _load();
  }

  void _connectionChanged() {
    final recovered = _wasOffline && !offlineStatus.value;
    _wasOffline = offlineStatus.value;
    if (recovered && mounted) _load();
  }

  @override
  void dispose() {
    offlineStatus.removeListener(_connectionChanged);
    super.dispose();
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
  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => RecipeEditor(
          recipe: _recipe!,
          householdId: widget.householdId,
          save: widget.save!,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _recipe = updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Recipe saved')));
    }
  }

  void _openRelated(Map<String, dynamic> row) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RecipeDetail(
        householdId: widget.householdId,
        recipeId: row['id'] as String,
        title: row['title'] as String,
        request: widget.request,
        save: widget.save,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      title: Text(_recipe?['title'] as String? ?? widget.title),
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
    final photos = distinctRecipePhotos(recipeRows(recipe['photos']));
    final nutrition = recipe['nutrition'] as Map<String, dynamic>?;
    final summary = recipeSummary(recipe);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    recipe['title'] as String,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                if (widget.save != null)
                  IconButton(
                    tooltip: 'Edit recipe',
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                Builder(
                  builder: (anchor) => IconButton(
                    tooltip: 'Share recipe',
                    icon: const Icon(Icons.share),
                    onPressed: _sharing ? null : () => _shareRecipe(anchor),
                  ),
                ),
              ],
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
              RecipePhotoGallery(photos: photos),
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
              'source_type',
              'source_title',
              'source_author',
              'source_url',
              'source_reference',
            ].any((key) => recipe[key] != null)) ...[
              _heading('Source'),
              for (final key in [
                'source_type',
                'source_title',
                'source_author',
                'source_url',
                'source_reference',
              ])
                if (recipe[key] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(
                      key == 'source_type'
                          ? recipeSourceLabel(recipe[key])
                          : recipe[key] as String,
                    ),
                  ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// WordPress exports often list the same original with several size suffixes.
/// Keep the selected cover first, and retain genuinely different source files.
List<Map<String, dynamic>> distinctRecipePhotos(
  List<Map<String, dynamic>> rows,
) {
  final ordered = [...rows]
    ..sort(
      (a, b) => ((b['is_cover'] as num?) ?? 0).compareTo(
        (a['is_cover'] as num?) ?? 0,
      ),
    );
  final seen = <String>{};
  return ordered.where((photo) {
    final url = photo['source_url'] as String?;
    if (url == null || url.isEmpty) return true;
    final uri = Uri.tryParse(url);
    final key = uri != null && uri.path.contains('/wp-content/uploads/')
        ? uri
              .replace(
                path: uri.path.replaceFirst(
                  RegExp(
                    r'-\d+x\d+(?=\.(?:jpe?g|png|webp)$)',
                    caseSensitive: false,
                  ),
                  '',
                ),
              )
              .toString()
        : url;
    return seen.add(key);
  }).toList();
}

class RecipePhotoGallery extends StatefulWidget {
  const RecipePhotoGallery({super.key, required this.photos});
  final List<Map<String, dynamic>> photos;
  @override
  State<RecipePhotoGallery> createState() => _RecipePhotoGalleryState();
}

class _RecipePhotoGalleryState extends State<RecipePhotoGallery> {
  final _pages = PageController();
  int _index = 0;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _move(int offset) => _pages.animateToPage(
    _index + offset,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    final height = (MediaQuery.sizeOf(context).height * .3).clamp(100.0, 240.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.photos.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) => SizedBox.expand(
                child: RecipePhoto(
                  url: widget.photos[index]['source_url'] as String?,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        if (widget.photos.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous photo',
                onPressed: _index > 0 ? () => _move(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_index + 1} / ${widget.photos.length}'),
              IconButton(
                tooltip: 'Next photo',
                onPressed: _index < widget.photos.length - 1
                    ? () => _move(1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        if (photo['caption'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              photo['caption'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (photo['attribution'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              photo['attribution'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
