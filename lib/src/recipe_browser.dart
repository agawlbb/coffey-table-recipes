import 'child_mode.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'api.dart';
import 'local_data.dart';
import 'recipe_menu.dart';
import 'cooking_mode.dart';
import 'offline_recipes.dart';
import 'recipe_sharing.dart';
import 'recipe_editor.dart';
import 'recipe_time.dart';
import 'recipe_value.dart';
import 'recipe_source_links.dart';
import 'recipe_variation.dart';
import 'recipe_import.dart';
import 'blank_recipe_detail.dart';
import 'recipe_favorites.dart';
import 'recipe_filter_dialog.dart';
import 'recipe_image_prefetch.dart';
import 'recipe_shopping.dart';
import 'meal_plan_actions.dart';
import 'shopping_ingredient.dart';

final recipePhotoCache = CacheManager(
  Config(
    'recentRecipePhotos',
    maxNrOfCacheObjects: 100,
    stalePeriod: const Duration(days: 90),
  ),
);

typedef RecipeRequest = Future<Map<String, dynamic>> Function(String path);

List<Map<String, dynamic>> recipeRows(Object? value) => (value as List? ?? [])
    .map((row) => Map<String, dynamic>.from(row as Map))
    .toList();

String recipeSourceLabel(Object? source) => switch (source) {
  'blank' => 'Blank recipe',
  'ai_text' => 'Pasted text',
  'ai_website' => 'Website link',
  'ai_file' => 'Uploaded file',
  'ai_camera' => 'Camera photo',
  'ai_reviewed' => 'Imported recipe',
  'ai_variation' => 'AI recipe variation',
  _ => source?.toString() ?? '',
};

bool isRecipeVariation(Map<String, dynamic> recipe) =>
    recipe['is_variation'] == true ||
    recipe['is_variation'] == 1 ||
    recipe['parent_recipe_id'] != null;

String recipeRelationshipLabel(
  Map<String, dynamic> recipe,
  Map<String, dynamic> related,
) {
  switch (related['relationship']) {
    case 'parent':
      return 'Parent recipe';
    case 'sibling':
      return 'Sibling variation';
    case 'child':
      return 'Child variation';
  }
  final parentId = recipe['parent_recipe_id']?.toString();
  final relativeParentId = related['parent_recipe_id']?.toString();
  if (parentId != null && related['id']?.toString() == parentId) {
    return 'Parent recipe';
  }
  if (parentId != null && relativeParentId == parentId) {
    return 'Sibling variation';
  }
  if (relativeParentId != null &&
      relativeParentId == recipe['id']?.toString()) {
    return 'Child variation';
  }
  return 'Related variation';
}

String recipeSummary(Map<String, dynamic> recipe) {
  final parts = <String>[];
  if (recipe['total_minutes'] != null) {
    parts.add(
      '${formatRecipeTime((num.tryParse('${recipe['total_minutes']}') ?? 0) * 60)} total',
    );
  } else {
    if (recipe['prep_minutes'] != null) {
      parts.add(
        '${formatRecipeTime((num.tryParse('${recipe['prep_minutes']}') ?? 0) * 60)} prep',
      );
    }
    if (recipe['cook_minutes'] != null) {
      parts.add(
        '${formatRecipeTime((num.tryParse('${recipe['cook_minutes']}') ?? 0) * 60)} cook',
      );
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
    this.localOnly = false,
    this.localRead,
    this.cachedRequest,
    this.menuBuilder,
    this.save,
    this.onSelect,
    this.mealPlanDestination,
    this.mealPlanToday,
    this.onViewMealPlan,
    this.onAddRecipe,
    this.onRecentlyDeleted,
    this.dragRecipes = false,
    this.onRecipeDragUpdate,
    this.onRecipeDragEnd,
  });
  final String householdId;
  final String householdName;
  final RecipeRequest request;
  final WidgetBuilder? menuBuilder;
  final Future<Map<String, dynamic>?> Function(String path)? cachedRequest;
  final RecipeSave? save;
  final bool embedded;
  final ValueChanged<Map<String, dynamic>>? onSelect;
  final String? mealPlanDestination;
  final DateTime? mealPlanToday;
  final VoidCallback? onViewMealPlan;
  final VoidCallback? onAddRecipe;
  final VoidCallback? onRecentlyDeleted;
  final bool dragRecipes;
  final ValueChanged<DragUpdateDetails>? onRecipeDragUpdate;
  final VoidCallback? onRecipeDragEnd;
  final bool localOnly;
  final Map<String, dynamic> Function(String path)? localRead;
  @override
  State<RecipeBrowser> createState() => _RecipeBrowserState();
}

class _RecipeBrowserState extends State<RecipeBrowser>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final List<Map<String, dynamic>> _recipes = [];
  int? _next;
  int _generation = 0;
  final Map<String, Map<String, dynamic>> _browseCache = {};
  String _query = '';
  Set<String> _favoritePeople = {};
  bool _blankOnly = false;
  bool _filterOpen = false;
  int get _filterCount => _favoritePeople.length + (_blankOnly ? 1 : 0);
  final List<Map<String, dynamic>> _trail = [];
  List<Map<String, dynamic>> _nodes = [];
  String get _scopeLabel =>
      _trail.isEmpty ? 'All recipes' : _trail.last['label'] as String;
  String? _error;
  String? _displayPath;
  bool _busy = true;
  bool _loadingMore = false;
  bool _wasOffline = false;
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      WidgetsBinding.instance.addObserver(this);
    }
    localDataChanges.addListener(_localChanged);
    _wasOffline = offlineStatus.value;
    if (mobileOfflineEnabled && !widget.localOnly) {
      offlineStatus.addListener(_connectionChanged);
    }
    _load(useCached: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    localDataChanges.removeListener(_localChanged);
    offlineStatus.removeListener(_connectionChanged);
    _search.dispose();
    super.dispose();
  }

  void _localChanged() {
    if (mounted &&
        (localDataChanges.value.startsWith('/me#') ||
            localDataChanges.value.startsWith(
              '/households/${widget.householdId}/recipes',
            ))) {
      _browseCache.clear();
      _load();
    }
  }

  void _connectionChanged() {
    final recovered = _wasOffline && !offlineStatus.value;
    _wasOffline = offlineStatus.value;
    if (recovered && mounted) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // The independent iOS share extension may have saved a recipe remotely.
      _load();
    }
  }

  Future<Map<String, dynamic>?> _cachedBrowse(String path) async {
    final memory = _browseCache[path];
    if (memory != null) return memory;
    try {
      return await widget.cachedRequest
          ?.call(path)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Local storage problems must not prevent an online read.
      return null;
    }
  }

  Future<Map<String, dynamic>> _browse(
    String path,
    bool useCached, {
    bool debounce = false,
  }) async {
    final generation = _generation;
    if (useCached) {
      final cached = await _cachedBrowse(path);
      if (cached != null) return cached;
    }
    // Saved-text searches return above immediately. Only debounce network misses.
    if ((useCached || debounce) &&
        (Uri.parse(path).queryParameters['q'] ?? '').isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || generation != _generation) return {};
    }
    // Include token refresh and cache persistence in the UI deadline too.
    final data = await widget
        .request(path)
        .timeout(const Duration(seconds: 30));
    if (mounted && generation == _generation) _browseCache[path] = data;
    return data;
  }

  Future<void> _load({bool more = false, bool useCached = false}) async {
    if (more && _loadingMore) return;
    final generation = ++_generation;
    if (!more) _query = _search.text.trim();
    final query = Uri(
      queryParameters: {
        'q': _query,
        'offset': '${more ? _next ?? 0 : 0}',
        'tree': more || _query.isNotEmpty || _blankOnly ? '0' : '1',
        'families': _favoritePeople.isEmpty && !_blankOnly ? '1' : '0',
        if (_blankOnly) 'blank': '1',
        if (_favoritePeople.isNotEmpty)
          'favorite_people': _favoritePeople.join(','),
        if (_trail.isNotEmpty) 'scope': '${_trail.last['id']}',
      },
    ).query;
    final path = '/households/${widget.householdId}/recipes?$query';
    bool current() => mounted && generation == _generation;
    List<Map<String, dynamic>> nodesFor(Map<String, dynamic> data) {
      final nodes = _query.isEmpty
          ? recipeRows(data['category_nodes'])
          : <Map<String, dynamic>>[];
      if (_trail.isNotEmpty) {
        nodes.sort((a, b) => _alphabeticalCompare(a, b, 'label'));
      }
      return nodes;
    }

    String recipePath() =>
        '/households/${widget.householdId}/recipes?${Uri(queryParameters: {...Uri.splitQueryString(query), 'tree': '0'}).query}';
    void display(Map<String, dynamic> data, List<Map<String, dynamic>> nodes) {
      if (!current()) return;
      setState(() {
        if (!more) _recipes.clear();
        _recipes.addAll(recipeRows(data['recipes']));
        _recipes.sort((a, b) => _alphabeticalCompare(a, b, 'title'));
        _next = data['next_offset'] as int?;
        if (!more) _nodes = nodes;
        _busy = false;
      });
    }

    setState(() {
      _error = null;
      _loadingMore = more;
      if (!more && _displayPath != path) {
        _recipes.clear();
        _nodes = [];
        _next = null;
      }
      if (!more) _displayPath = path;
      _busy = _recipes.isEmpty && _nodes.isEmpty;
    });
    try {
      if (widget.localOnly) {
        final data = widget.localRead != null
            ? widget.localRead!(path)
            : await widget.request(path);
        if (!current()) return;
        final nodes = nodesFor(data);
        if (!more && _query.isEmpty && data['view'] == 'categories') {
          final recipes = widget.localRead != null
              ? widget.localRead!(recipePath())
              : await widget.request(recipePath());
          display(recipes, nodes);
        } else {
          display(data, nodes);
        }
        return;
      }
      if (!more) {
        final cached = await _cachedBrowse(path);
        if (!current()) return;
        if (cached != null) {
          final nodes = nodesFor(cached);
          display(
            cached['view'] == 'categories'
                ? {
                    ...cached,
                    'recipes': List.of(_recipes),
                    'next_offset': _next,
                  }
                : cached,
            nodes,
          );
          var complete = cached['_cache_needs_refresh'] != true;
          if (_query.isEmpty && cached['view'] == 'categories') {
            final recipes = await _cachedBrowse(recipePath());
            if (!current()) return;
            if (recipes != null) display(recipes, nodes);
            complete =
                complete &&
                recipes != null &&
                recipes['_cache_needs_refresh'] != true;
          }
          if (useCached && complete) {
            unawaited(_loadCategoryImages(nodes, generation));
            return;
          }
        }
        if (!useCached) _browseCache.clear();
      }
      var data = await _browse(path, more, debounce: useCached && !more);
      if (!mounted || generation != _generation) return;
      final nodes = nodesFor(data);
      display(
        data['view'] == 'categories'
            ? {...data, 'recipes': List.of(_recipes), 'next_offset': _next}
            : data,
        nodes,
      );
      if (!more && _query.isEmpty && data['view'] == 'categories') {
        data = await _browse(recipePath(), false);
        display(data, nodes);
      }
      if (!mounted || generation != _generation) return;
      if (!more) unawaited(_loadCategoryImages(nodes, generation));
    } catch (error, stack) {
      if (widget.localOnly && error is! ApiException) {
        debugPrint(
          'Local recipe read failed: ${error.runtimeType}: $error\n$stack',
        );
      }
      if (mounted && generation == _generation) {
        setState(() {
          if (error is ApiException && [401, 403, 404].contains(error.status)) {
            _recipes.clear();
            _nodes = [];
            _next = null;
            _browseCache.clear();
          }
          _error = error is ApiException
              ? error.message
              : widget.localOnly
              ? 'The local recipe database could not be read.'
              : 'Recipe data could not be read.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadCategoryImages(
    List<Map<String, dynamic>> nodes,
    int generation,
  ) async {
    if (widget.save == null || childMode.value) return;
    for (final category in nodes.where(
      (node) => node['needs_ai_image'] == true && node['image_url'] == null,
    )) {
      if (!mounted || generation != _generation || childMode.value) return;
      try {
        final image = await widget.save!(
          '/households/${widget.householdId}/category-image',
          {'category_id': category['id'].toString()},
        );
        if (!mounted || generation != _generation) return;
        setState(() => category['image_url'] = image['image_url']);
      } catch (_) {
        // Text remains usable while artwork is unavailable.
      }
    }
  }

  int _alphabeticalCompare(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    String field,
  ) {
    final order = recipeValue(a[field])
        .trim()
        .toLowerCase()
        .compareTo(recipeValue(b[field]).trim().toLowerCase());
    return order != 0
        ? order
        : recipeValue(a['id']).compareTo(recipeValue(b['id']));
  }

  void _enterCategory(Map<String, dynamic> category) {
    mealPlanNotices.dismiss();
    setState(() {
      _trail.add(category);
      _search.clear();
      _next = null;
    });
    _load(useCached: true);
  }

  void _back() {
    _returnToLevel(_trail.isEmpty ? 0 : _trail.length - 1);
  }

  void _returnToLevel(int depth) {
    mealPlanNotices.dismiss();
    FocusScope.of(context).unfocus();
    setState(() {
      _trail.removeRange(depth, _trail.length);
      _search.clear();
      _next = null;
    });
    _load(useCached: true);
  }

  Future<void> _filters() async {
    if (_filterOpen) return;
    _filterOpen = true;
    FocusScope.of(context).unfocus();
    try {
      final selected = await showDialog<RecipeFilterSelection>(
        context: context,
        builder: (_) => RecipeFilterDialog(
          blankOnly: _blankOnly,
          favoritePeople: _favoritePeople,
          loadPeople: () async => recipeRows(
            (widget.localRead != null
                ? widget.localRead!('/households/${widget.householdId}/people')
                : await widget.request(
                    '/households/${widget.householdId}/people',
                  ))['people'],
          ),
        ),
      );
      if (!mounted ||
          selected == null ||
          (selected.blankOnly == _blankOnly &&
              setEquals(selected.favoritePeople, _favoritePeople))) {
        return;
      }
      setState(() {
        _blankOnly = selected.blankOnly;
        _favoritePeople = Set.from(selected.favoritePeople);
      });
      _load();
    } finally {
      _filterOpen = false;
    }
  }

  Future<void> _planRecipe(Map<String, dynamic> recipe) async {
    final add = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('Add to meal plan'),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (add == true && mounted) {
      await addDatedMeal(
        context,
        householdId: widget.householdId,
        recipe: recipe,
        request: widget.request,
        save: widget.save!,
        viewPlan: widget.onViewMealPlan,
      );
    }
  }

  bool _selectingMeal = false;
  Future<void> _open(Map<String, dynamic> recipe) async {
    if (widget.onSelect != null) {
      if (_selectingMeal) return;
      _selectingMeal = true;
      try {
        final data = await widget.request(
          '/households/${widget.householdId}/recipes/${recipe['id']}',
        );
        if (!mounted) return;
        final full = Map<String, dynamic>.from(data['recipe'] as Map);
        final result = widget.mealPlanDestination == null
            ? await chooseDatedMealRecipe(
                context,
                full,
                today: widget.mealPlanToday ?? DateTime.now(),
              )
            : await confirmMealRecipe(
                context,
                full,
                destination: widget.mealPlanDestination!,
              );
        if (mounted && result != null) widget.onSelect!(result);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      } finally {
        _selectingMeal = false;
      }
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetail(
          householdId: widget.householdId,
          recipeId: recipe['id'] as String,
          title: recipe['title'] as String,
          request: widget.request,
          cachedRequest: widget.cachedRequest,
          localRead: widget.localRead,
          save: widget.save,
          menuBuilder: widget.menuBuilder,
          onViewMealPlan: widget.onViewMealPlan,
          onChanged: () {
            if (mounted) _load();
          },
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
              if (!widget.localOnly)
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
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              mouseCursor: kIsWeb
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.text,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                FocusScope.of(context).unfocus();
                _load(useCached: true);
              },
              onChanged: (_) => _load(useCached: true),
              decoration: InputDecoration(
                labelText: _trail.isEmpty
                    ? 'Search all recipes'
                    : 'Search ${_scopeLabel.toLowerCase()}',
                hintText: 'Title, ingredient, cuisine or technique',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _filterCount == 0
                          ? 'Filters'
                          : 'Filters ($_filterCount selected)',
                      onPressed: _filters,
                      icon: Icon(
                        _filterCount == 0
                            ? Icons.filter_list
                            : Icons.filter_list_alt,
                        color: _filterCount == 0
                            ? null
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (_search.text.isNotEmpty || _query.isNotEmpty)
                      IconButton(
                        onPressed: () {
                          _search.clear();
                          _load(useCached: true);
                        },
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                      ),
                    IconButton(
                      onPressed: () => _load(useCached: true),
                      tooltip: 'Search recipes',
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.onSelect == null &&
              widget.mealPlanDestination == null &&
              (widget.onAddRecipe != null || widget.onRecentlyDeleted != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Wrap(
                spacing: 12,
                children: [
                  if (widget.onAddRecipe != null && !childModeOf(context))
                    ValueListenableBuilder<bool>(
                      valueListenable: offlineStatus,
                      builder: (context, offline, _) => TextButton.icon(
                        onPressed: childModeOf(context)
                            ? null
                            : widget.onAddRecipe,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add recipe'),
                      ),
                    ),
                  if (widget.onRecentlyDeleted != null)
                    TextButton.icon(
                      onPressed: widget.onRecentlyDeleted,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Recently deleted'),
                    ),
                ],
              ),
            ),
          if (_filterCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_blankOnly)
                      InputChip(
                        label: const Text('Blank recipes only'),
                        onPressed: _filters,
                        deleteButtonTooltipMessage:
                            'Remove blank recipe filter',
                        onDeleted: () {
                          setState(() => _blankOnly = false);
                          _load();
                        },
                      ),
                    if (_favoritePeople.isNotEmpty)
                      InputChip(
                        avatar: const Icon(Icons.favorite, size: 18),
                        label: Text('Favorites (${_favoritePeople.length})'),
                        onPressed: _filters,
                        deleteButtonTooltipMessage: 'Remove favorite filters',
                        onDeleted: () {
                          setState(_favoritePeople.clear);
                          _load();
                        },
                      ),
                  ],
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
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back one level',
                    ),
                  for (var depth = 0; depth <= _trail.length; depth++) ...[
                    if (depth > 0) const Icon(Icons.chevron_right, size: 18),
                    TextButton(
                      key: ValueKey('recipe-breadcrumb-$depth'),
                      onPressed: () => _returnToLevel(depth),
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
          if (widget.mealPlanDestination != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 20, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add to ${widget.mealPlanDestination}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
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
                    child: Text(
                      widget.localOnly ? 'Read local data again' : 'Retry',
                    ),
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
                      onPressed: _busy || _loadingMore
                          ? null
                          : () => _load(more: true),
                      child: const Text('Load more recipes'),
                    ),
                  );
                }
                final recipe = _recipes[recipeIndex];
                final card = Card(
                  color: const Color(0xfffff9ee),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(recipe),
                    onLongPress: childModeOf(context)
                        ? null
                        : widget.save == null ||
                              widget.onSelect != null ||
                              widget.dragRecipes
                        ? null
                        : () => _planRecipe(recipe),
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
                                if (isRecipeVariation(recipe))
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text('Variation'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                return widget.dragRecipes && !childModeOf(context)
                    ? Draggable<Map<String, dynamic>>(
                        data: {'recipe': recipe},
                        onDragUpdate: widget.onRecipeDragUpdate,
                        onDragEnd: (_) => widget.onRecipeDragEnd?.call(),
                        feedback: Material(
                          borderRadius: BorderRadius.circular(24),
                          child: SizedBox(width: 280, child: card),
                        ),
                        child: card,
                      )
                    : card;
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
    childModeOf(context);
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
    this.cachedRequest,
    this.localRead,
    this.save,
    this.onChanged,
    this.menuBuilder,
    this.onViewMealPlan,
  });
  final String householdId;
  final String recipeId;
  final String title;
  final RecipeRequest request;
  final Map<String, dynamic> Function(String path)? localRead;
  final Future<Map<String, dynamic>?> Function(String path)? cachedRequest;
  final RecipeSave? save;
  final VoidCallback? onChanged;
  final WidgetBuilder? menuBuilder;
  final VoidCallback? onViewMealPlan;
  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends State<RecipeDetail> {
  Future<void> _shoppingIngredients(List<Map<String, dynamic>> ingredients) =>
      showRecipeShopping(
        context,
        householdId: widget.householdId,
        request: widget.request,
        save: widget.save!,
        ingredients: ingredients.map(ShoppingIngredient.fromRecipe).toList(),
      );
  List<Map<String, dynamic>> _favoriteMembers = [];
  String? _currentPerson;
  bool _favoriteBusy = false;
  String get _favoritesPath =>
      '/households/${widget.householdId}/recipes/${widget.recipeId}/favorites';
  bool _isFavorite(Map<String, dynamic> p) =>
      p['favorite'] == true || p['favorite'] == 1 || p['favorite'] == '1';
  void _acceptFavorites(Map<String, dynamic> data) {
    _favoriteMembers = recipeRows(data['people']);
    _currentPerson = data['current_person_id']?.toString();
  }

  Future<void> _loadFavorites() async {
    if (widget.save == null) return;
    try {
      final data = widget.localRead != null
          ? widget.localRead!(_favoritesPath)
          : await widget.request(_favoritesPath);
      if (mounted) setState(() => _acceptFavorites(data));
    } catch (_) {
      /* Recipe content stays available offline. Writes retry the read. */
    }
  }

  Future<void> _favorite({bool household = false}) async {
    setState(() => _favoriteBusy = true);
    try {
      final data = await widget.request(_favoritesPath);
      if (!mounted) return;
      setState(() => _acceptFavorites(data));
      if (household) {
        final people = await chooseHouseholdFavorites(
          context,
          _favoriteMembers,
        );
        if (people == null) return;
        for (final p in people) {
          final original = _favoriteMembers.firstWhere(
            (m) => m['id'] == p['id'],
          );
          if (_isFavorite(original) == _isFavorite(p)) continue;
          final result = await widget.save!(_favoritesPath, {
            'person_id': p['id'],
            'favorite': _isFavorite(p),
          });
          if (mounted) setState(() => _acceptFavorites(result));
        }
      } else {
        final own = _favoriteMembers
            .where((p) => '${p['id']}' == _currentPerson)
            .firstOrNull;
        if (own == null) {
          throw StateError('Your household person was not found.');
        }
        final result = await widget.save!(_favoritesPath, {
          'person_id': _currentPerson,
          'favorite': !_isFavorite(own),
        });
        if (mounted) setState(() => _acceptFavorites(result));
      }
      widget.onChanged?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update favorites: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  bool _sharing = false;
  bool _deleting = false;
  bool _variationOpen = false;
  bool _openingRelated = false;

  Future<void> _delete() async {
    if (childModeOf(context)) return;
    if (offlineStatus.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to the internet to delete a recipe.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: const Text(
          'Remove this recipe from this household? Other households keep it. If this is the last household, it moves to Recently Deleted for 30 days before permanent removal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete recipe'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final path = '/households/${widget.householdId}/recipes/${widget.recipeId}';
    final save = widget.save!;
    final onChanged = widget.onChanged;
    try {
      final removal = await save('$path/delete', {
        'revision': _recipe!['revision'],
      });
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removal.containsKey('purge_after') && removal['purge_after'] == null
                ? 'Recipe removed from this household'
                : 'Recipe moved to Recently Deleted',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await save(
                  removal.containsKey('purge_after') &&
                          removal['purge_after'] == null
                      ? '$path/attach'
                      : '$path/restore',
                  {},
                );
                onChanged?.call();
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Recipe restored')),
                  );
                }
              } catch (error) {
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        error is ApiException ? error.message : 'Could not restore recipe. Check your connection and retry.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Could not delete recipe. Check your connection and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _explainTimer(Map<String, dynamic> recipe) async {
    if (childMode.value) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use timers in cooking mode'),
        content: const Text('Open in cooking mode to use timers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open cooking mode'),
          ),
        ],
      ),
    );
    if (open != true || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            CookingMode(recipe: recipe, menuBuilder: widget.menuBuilder),
      ),
    );
  }

  Future<void> _shareRecipe(BuildContext anchor) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Send a link'),
              subtitle: const Text(
                'Anyone with the link can view this recipe.',
              ),
              onTap: () => Navigator.pop(context, 'send'),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Copy HTML link'),
              onTap: () => Navigator.pop(context, 'html'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted || !anchor.mounted) return;
    final title = '${_recipe?['title'] ?? widget.title}';
    if (choice == 'html') {
      await Clipboard.setData(
        ClipboardData(text: recipeShareHtml(widget.recipeId, title)),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('HTML link copied')));
      }
      return;
    }
    final box = anchor.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      final link = recipeShareLink(widget.recipeId);
      var status = ShareResultStatus.unavailable;
      try {
        if (await shareRecipeHtml(widget.recipeId, title, origin: origin)) {
          status = ShareResultStatus.success;
        } else {
          final result = await SharePlus.instance.share(
            ShareParams(
              text: '$title\n$link',
              title: title,
              subject: title,
              sharePositionOrigin: origin,
            ),
          );
          status = result.status;
        }
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
  int _imagePrefetchGeneration = 0;
  String? _error;
  bool _wasOffline = false;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    localDataChanges.addListener(_localChanged);
    _wasOffline = offlineStatus.value;
    if (mobileOfflineEnabled) offlineStatus.addListener(_connectionChanged);
    _load();
  }

  void _localChanged() {
    if (mounted &&
        (localDataChanges.value.startsWith('/me#') ||
            localDataChanges.value.startsWith(
              '/households/${widget.householdId}/recipes',
            ))) {
      _load();
    }
  }

  void _connectionChanged() {
    final recovered = _wasOffline && !offlineStatus.value;
    _wasOffline = offlineStatus.value;
    if (recovered && mounted) _load();
  }

  @override
  void dispose() {
    localDataChanges.removeListener(_localChanged);
    offlineStatus.removeListener(_connectionChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    bool current() => mounted && generation == _loadGeneration;
    setState(() {
      _error = null;
    });
    final path = '/households/${widget.householdId}/recipes/${widget.recipeId}';
    void display(Map<String, dynamic> data) {
      if (!current() || data['recipe'] is! Map) return;
      setState(
        () => _recipe = Map<String, dynamic>.from(data['recipe'] as Map),
      );
    }

    if (widget.localRead != null) {
      try {
        display(widget.localRead!(path));
        if (_recipe == null) throw StateError('Missing local recipe');
        _prefetchImages(_recipe!);
        _loadFavorites();
      } catch (error) {
        if (current()) {
          final denied =
              error is ApiException && [401, 403, 404].contains(error.status);
          setState(() {
            if (denied) _recipe = null;
            if (_recipe == null) {
              _error = error is ApiException
                  ? error.message
                  : 'The local recipe database could not be read.';
            }
          });
        }
      }
      return;
    }

    try {
      final cached = await widget.cachedRequest
          ?.call(path)
          .timeout(const Duration(seconds: 2));
      if (!current()) return;
      if (cached != null) display(cached);
    } catch (_) {
      // A failed cache read must not block the online request.
    }
    try {
      if (!current()) return;
      final data = await widget
          .request(path)
          .timeout(const Duration(seconds: 30));
      if (current()) {
        display(data);
        _prefetchImages(_recipe!);
        _loadFavorites();
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        final denied =
            error is ApiException && [401, 403, 404].contains(error.status);
        if (_recipe != null && !denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'The saved recipe is still available. An updated copy could not be read.',
              ),
              action: SnackBarAction(label: 'Retry', onPressed: _load),
            ),
          );
          return;
        }
        setState(() {
          if (denied) _recipe = null;
          _error = error is ApiException
              ? error.message
              : 'Recipe data could not be read on this device.';
        });
      }
    }
  }

  void _prefetchImages(Map<String, dynamic> recipe) {
    final generation = ++_imagePrefetchGeneration;
    bool active() =>
        mounted &&
        generation == _imagePrefetchGeneration &&
        !offlineStatus.value;
    unawaited(
      prefetchRecipeImages(
        recipe: recipe,
        active: active,
        loadRecipe: (id) async {
          final data = await widget.request(
            '/households/${widget.householdId}/recipes/$id',
          );
          return data['recipe'] as Map<String, dynamic>;
        },
        cacheImage: (url) async {
          if (mobileOfflineEnabled) {
            await recipePhotoCache.getSingleFile(url);
          } else if (active()) {
            await precacheImage(NetworkImage(url), context, onError: (_, _) {});
          }
        },
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
  Future<void> _attach() async {
    if (childModeOf(context)) return;
    try {
      final data = await widget.save!(
        '/households/${widget.householdId}/recipes/${widget.recipeId}/attach',
        {},
      );
      if (!mounted) return;
      setState(() => _recipe = data['recipe'] as Map<String, dynamic>);
      widget.onChanged?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Could not add recipe. Try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _edit() async {
    if (childModeOf(context)) return;
    try {
      final metadata = await widget.request(
        '/households/${widget.householdId}/recipes/${widget.recipeId}/edit-options',
      );
      if (!mounted) return;
      if (metadata['edit_options'] != null) {
        _recipe!['edit_options'] = metadata['edit_options'];
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Sign in again to edit this recipe.',
            ),
          ),
        );
      }
      return;
    }
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
      _prefetchImages(updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Recipe saved')));
    }
  }

  Future<void> _importBlank(String kind) async {
    final saved = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeImport(
          householdId: widget.householdId,
          request: widget.save!,
          blankRecipe: _recipe,
          initialKind: kind,
        ),
      ),
    );
    if (saved != null && mounted) {
      widget.onChanged?.call();
      await _load();
    }
  }

  Future<void> _requestVariation() async {
    if (childModeOf(context)) return;
    if (_variationOpen || _deleting || widget.save == null) return;
    if (offlineStatus.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to the internet to request a variation.'),
        ),
      );
      return;
    }
    setState(() => _variationOpen = true);
    try {
      final saved = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => RecipeVariation(
            householdId: widget.householdId,
            parentRecipeId: widget.recipeId,
            parentTitle: _recipe!['title'] as String,
            request: widget.save!,
          ),
        ),
      );
      if (saved == null || !mounted) return;
      widget.onChanged?.call();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Variation saved')));
      await _openRelated(saved);
    } finally {
      if (mounted) setState(() => _variationOpen = false);
    }
  }

  Future<void> _openRelated(Map<String, dynamic> row) async {
    if (_openingRelated) return;
    setState(() => _openingRelated = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecipeDetail(
            householdId: widget.householdId,
            recipeId: row['id'] as String,
            title: row['title'] as String,
            request: widget.request,
            cachedRequest: widget.cachedRequest,
            localRead: widget.localRead,
            save: widget.save,
            menuBuilder: widget.menuBuilder,
            onChanged: widget.onChanged,
            onViewMealPlan: widget.onViewMealPlan,
          ),
        ),
      );
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _openingRelated = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: widget.menuBuilder?.call(context),
    appBar: AppBar(
      leadingWidth: widget.menuBuilder == null ? null : 96,
      leading: widget.menuBuilder == null
          ? BackButton(onPressed: () => Navigator.of(context).pop())
          : const RecipeMenuLeading(),
      title: Text(
        _recipe?['source_type'] == 'blank'
            ? 'Blank recipe'
            : _recipe?['title'] as String? ?? widget.title,
      ),
      actions: [
        if (!childModeOf(context) &&
            _recipe?['source_type'] == 'blank' &&
            widget.save != null &&
            _recipe?['in_household'] != false) ...[
          IconButton(
            tooltip: 'Edit name, category or picture',
            onPressed: _deleting || childModeOf(context) ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete recipe',
            onPressed: _deleting || childModeOf(context) ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ],
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
    if (recipe['source_type'] == 'blank') {
      final editable =
          widget.save != null && recipe['in_household'] != false && !_deleting;
      return BlankRecipeDetail(
        title: recipe['title'] as String,
        photos: distinctRecipePhotos(recipeRows(recipe['photos'])),
        favorite: _favoriteMembers.any(
          (p) => '${p['id']}' == _currentPerson && _isFavorite(p),
        ),
        favoriteNames: _favoriteMembers
            .where(_isFavorite)
            .map((p) => p['display_name'])
            .join(' and '),
        showFavorite: widget.save != null && recipe['in_household'] != false,
        onFavorite: editable && !_favoriteBusy ? () => _favorite() : null,
        onHouseholdFavorites: editable && !_favoriteBusy
            ? () => _favorite(household: true)
            : null,
        onPicture: editable ? _edit : null,
        onMealPlan: editable
            ? () => addDatedMeal(
                context,
                householdId: widget.householdId,
                recipe: recipe,
                request: widget.request,
                save: widget.save!,
                viewPlan: widget.onViewMealPlan,
                exactRecipe: true,
              )
            : null,
        onImport: editable ? _importBlank : null,
        onAttach: widget.save != null && recipe['in_household'] == false
            ? _attach
            : null,
        offline: offlineStatus.value,
      );
    }
    final ingredients = recipeRows(recipe['ingredients']);
    final groups = recipeRows(recipe['groups']);
    final steps = recipeRows(recipe['steps']);
    final actions = recipeRows(recipe['actions']);
    final photos = distinctRecipePhotos(recipeRows(recipe['photos']));
    final nutrition = recipe['nutrition'] as Map<String, dynamic>?;
    final summary = recipeSummary(recipe);
    final family = recipeRows(recipe['variation_family'] ?? recipe['related'])
        .where((row) => row['id'].toString() != recipe['id'].toString())
        .toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!childModeOf(context) &&
                    widget.save != null &&
                    _recipe?['in_household'] == false)
                  TextButton.icon(
                    onPressed: childModeOf(context) ? null : _attach,
                    icon: const Icon(Icons.add),
                    label: const Text('Add to my household'),
                  ),
                Row(
                  children: [
                    if (!childModeOf(context) &&
                        widget.save != null &&
                        _recipe?['in_household'] != false)
                      IconButton(
                        tooltip: 'Edit recipe',
                        onPressed: _deleting || childModeOf(context)
                            ? null
                            : _edit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    Builder(
                      builder: (anchor) => IconButton(
                        tooltip: 'Share recipe',
                        icon: const Icon(Icons.share),
                        onPressed: _sharing ? null : () => _shareRecipe(anchor),
                      ),
                    ),
                    if (!childModeOf(context) &&
                        widget.save != null &&
                        _recipe?['in_household'] != false)
                      IconButton(
                        tooltip: 'Delete recipe',
                        onPressed: _deleting || childModeOf(context)
                            ? null
                            : _delete,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    if (widget.save != null && recipe['in_household'] != false)
                      IconButton(
                        tooltip: 'Favorite (hold for household)',
                        onPressed: _favoriteBusy ? null : () => _favorite(),
                        onLongPress: _favoriteBusy
                            ? null
                            : () => _favorite(household: true),
                        icon: Icon(
                          _favoriteMembers.any(
                                (p) =>
                                    '${p['id']}' == _currentPerson &&
                                    _isFavorite(p),
                              )
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                      ),
                    if (family.isNotEmpty)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: PopupMenuButton<String>(
                            tooltip: 'Choose a recipe variation',
                            enabled: !_openingRelated && !_deleting,
                            onSelected: (id) {
                              if (id == recipe['id'].toString()) return;
                              _openRelated(
                                family.firstWhere(
                                  (row) => row['id'].toString() == id,
                                ),
                              );
                            },
                            itemBuilder: (_) => [
                              CheckedPopupMenuItem(
                                value: recipe['id'].toString(),
                                checked: true,
                                child: Text(recipe['title'] as String),
                              ),
                              for (final row in family)
                                PopupMenuItem(
                                  value: row['id'].toString(),
                                  child: Text(row['title'] as String),
                                ),
                            ],
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 44),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xffa12c21)
                                      .withValues(alpha: .35),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Variations',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xffa12c21),
                                          ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_drop_down,
                                    size: 24,
                                    color: Color(0xffa12c21),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!childModeOf(context))
              FilledButton.icon(
                onPressed: childModeOf(context) || steps.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CookingMode(
                            recipe: recipe,
                            menuBuilder: widget.menuBuilder,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.soup_kitchen_outlined),
                label: const Text('Start cooking'),
              ),
            if (!childModeOf(context) &&
                widget.save != null &&
                recipe['in_household'] != false)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _deleting || childModeOf(context)
                            ? null
                            : () => addDatedMeal(
                                context,
                                householdId: widget.householdId,
                                recipe: recipe,
                                request: widget.request,
                                save: widget.save!,
                                viewPlan: widget.onViewMealPlan,
                                exactRecipe: true,
                              ),
                        child: const Text(
                          'Add to meal plan',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            childModeOf(context) || _deleting || _variationOpen
                            ? null
                            : _requestVariation,
                        child: const Text(
                          'Request variation',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (recipe['description'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  recipe['description'] as String,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            if (_favoriteMembers.any(_isFavorite))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Favorite of ${_favoriteMembers.where(_isFavorite).map((p) => p['display_name']).join(' and ')}',
                ),
              ),
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(summary),
              ),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 20),
              RecipePhotoGallery(photos: photos),
            ],
            Wrap(
              spacing: 8,
              children: [
                if (isRecipeVariation(recipe))
                  const Chip(label: Text('Variation')),
                for (final tag in recipeRows(recipe['tags']))
                  if (!isRecipeVariation(recipe) ||
                      '${tag['label']}'.trim().toLowerCase() != 'variation')
                    Chip(label: Text('${tag['label']}')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 28, bottom: 12),
              child: Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Ingredients',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (!childModeOf(context) &&
                      widget.save != null &&
                      widget.householdId.isNotEmpty)
                    TextButton.icon(
                      onPressed: childModeOf(context) || ingredients.isEmpty
                          ? null
                          : () => _shoppingIngredients(ingredients),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Add to shopping list'),
                    ),
                ],
              ),
            ),

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
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              for (final ingredient in ingredients.where(
                (i) => i['group_id'] == groupId,
              ))
                Padding(
                  padding: EdgeInsets.only(
                    top: 6,
                    bottom: 6,
                    left: groupId == null ? 0 : 16,
                  ),
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
                    if (step['section_title']?.toString().trim().isNotEmpty ==
                        true)
                      Text(
                        '${step['position']}. ${step['section_title']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    Text(
                      '${step['section_title']?.toString().trim().isNotEmpty == true ? '' : '${step['position']}. '}${step['instruction']}',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(height: 1.6),
                    ),
                    for (final action in actions.where(
                      (a) => a['step_id'] == step['id'],
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: InputChip(
                          onPressed:
                              !childModeOf(context) &&
                                  (num.tryParse(
                                            '${action['duration_seconds']}',
                                          ) ??
                                          0) >
                                      0
                              ? () => _explainTimer(recipe)
                              : null,
                          avatar: Icon(
                            action['temperature_value'] != null
                                ? Icons.thermostat
                                : Icons.timer_outlined,
                          ),
                          label: Text(
                            [
                              if (action['label'] != null) '${action['label']}',
                              if (action['duration_seconds'] != null)
                                formatRecipeTime(action['duration_seconds']),
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
                    child: RecipeSourceText(
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
    childModeOf(context);
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
