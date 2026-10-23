import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'api.dart';
import 'local_data.dart';
import 'meal_plan_actions.dart';
import 'meal_plan_ingredients.dart';
import 'recipe_browser.dart';
import 'recipe_editor.dart';
import 'recipe_shopping.dart';
import 'shopping_item_id.dart';
import 'shopping_ingredient.dart';

class MealPlanner extends StatefulWidget {
  const MealPlanner({
    super.key,
    required this.householdId,
    required this.householdName,
    required this.request,
    required this.save,
    this.active = true,
    this.now,
  });
  final String householdId, householdName;
  final RecipeRequest request;
  final RecipeSave save;
  final bool active;
  final DateTime Function()? now;
  @override
  State<MealPlanner> createState() => _MealPlannerState();
}

class _MealPlannerState extends State<MealPlanner> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _scrollArea = GlobalKey();
  final _center = GlobalKey();
  final _toolbar = GlobalKey();
  final _pressedPointers = <int>{};
  int? _dragPointer;
  ModalRoute<dynamic>? _route;
  bool _background = false;
  List<Map<String, dynamic>> _entries = [];
  late DateTime _today;
  int _revision = 0, _pastDays = 30, _futureDays = 45, _generation = 0;
  bool _loading = true, _saving = false, _fetching = false;
  bool _ready = false;
  int _accessEpoch = 0;
  String? _error;
  Timer? _refresh, _dragScroll;
  Offset? _dragPosition;
  String get _path => '/households/${widget.householdId}/meal-plan';

  // A missing route/recipe is not evidence that household membership was lost.
  // A 401 interrupts session readiness, but does not remove the household or
  // sign the user out: a successful retry can restore the plan.
  bool _invalidateAccess(Object error) {
    if (error is! ApiException ||
        !(error.status == 401 ||
            (error.status == 404 && error.code == 'household_not_found') ||
            (error.status == 403 &&
                (error.code == 'account_disabled' ||
                    error.code == 'household_access_removed')))) {
      return false;
    }
    if (!mounted) return true;
    setState(() {
      _ready = false;
      _entries = [];
      _revision = 0;
      _accessEpoch++;
      _generation++;
      _fetching = false;
      _loading = false;
      _error = error.message;
    });
    _stopDragScroll();
    return true;
  }

  bool _usable(int epoch) => mounted && _ready && epoch == _accessEpoch;
  @override
  void initState() {
    super.initState();
    final now = widget.now?.call() ?? DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_trackPointer);
    localDataChanges.addListener(_localChanged);
    _scroll.addListener(_extend);
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.active && !_saving && !_loading && !_fetching) {
        _load(quiet: true);
      }
    });
  }

  @override
  void didUpdateWidget(MealPlanner old) {
    super.didUpdateWidget(old);
    if (!widget.active && old.active) _stopDragScroll();
    if (widget.active && !old.active) _load(quiet: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (!(_route?.isCurrent ?? true)) _stopDragScroll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    if (_background) {
      _stopDragScroll();
      _pressedPointers.clear();
    }
    if (state == AppLifecycleState.resumed && widget.active) _load(quiet: true);
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_trackPointer);
    localDataChanges.removeListener(_localChanged);
    _refresh?.cancel();
    _stopDragScroll();
    _scroll.dispose();
    super.dispose();
  }

  void _localChanged() {
    if (mounted &&
        !_saving &&
        (localDataChanges.value.startsWith(_path) ||
            localDataChanges.value.startsWith('/me#'))) {
      _load(quiet: true);
    }
  }

  DateTime _day(int offset) =>
      DateTime(_today.year, _today.month, _today.day + offset);
  String _range() =>
      'from=${mealPlanDate(_day(-_pastDays))}&to=${mealPlanDate(_day(_futureDays))}';
  Future<bool> _load({bool quiet = false}) async {
    final generation = ++_generation;
    _fetching = true;
    if (!quiet && !_ready && mounted) setState(() => _loading = true);
    try {
      final data = await widget.request('$_path?${_range()}');
      if (!mounted || generation != _generation) return false;
      final today = DateTime.tryParse('${data['today']}');
      setState(() {
        if (today != null) _today = today;
        _revision = (data['revision'] as num).toInt();
        _entries = recipeRows(data['entries'])
            .map((e) => {...e, '_revision': _revision})
            .toList();
        _error = null;
        _loading = false;
        _ready = true;
      });
      return true;
    } catch (error) {
      if (mounted && generation == _generation) {
        if (_invalidateAccess(error)) return false;
        setState(() {
          _error = error is ApiException
              ? error.message
              : 'Could not load the meal plan. Try again.';
          _loading = false;
        });
      }
      return false;
    } finally {
      if (generation == _generation) _fetching = false;
    }
  }

  void _extend() {
    if (_loading || _fetching || !_scroll.hasClients) return;
    if (_scroll.position.extentBefore < 300) {
      setState(() => _pastDays += 30);
      _load(quiet: true);
    } else if (_scroll.position.extentAfter < 300) {
      setState(() => _futureDays += 30);
      _load(quiet: true);
    }
  }

  bool _past(String? date) =>
      date != null && date.compareTo(mealPlanDate(_today)) < 0;
  Future<bool> _confirmPast() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change this past meal?'),
          content: const Text('This will update your cooking history.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Change'),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _change(
    Map<String, dynamic> operation, {
    String? oldDate,
    bool confirmed = false,
  }) async {
    if (_saving || !_ready) return false;
    final epoch = _accessEpoch;
    final expectedRevision = operation['_revision'] ?? _revision;
    final past = _past(oldDate) || _past(operation['date'] as String?);
    if (past && !confirmed && !await _confirmPast()) return false;
    if (!_usable(epoch)) return false;
    setState(() => _saving = true);
    _generation++; // In-flight polls must not replace a mutation's newer revision.
    try {
      final result = await widget.save(_path, {
        ...operation,
        'revision': expectedRevision,
        'confirm_past': past || confirmed,
      });
      if (!_usable(epoch)) return false;
      _revision = (result['revision'] as num).toInt();
      await _load(quiet: true);
      return true;
    } on ApiException catch (error) {
      if (!_usable(epoch)) return false;
      if (_invalidateAccess(error)) return false;
      await _load(quiet: true);
      if (!_usable(epoch)) return false;
      if (error.code == 'past_confirmation_required' && !confirmed) {
        setState(() => _saving = false);
        if (await _confirmPast() && _usable(epoch)) {
          return _change(operation, oldDate: oldDate, confirmed: true);
        }
        return false;
      }
      _message(error.message);
      return false;
    } catch (_) {
      if (mounted) {
        _message('Could not save the meal plan. Refresh before trying again.');
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _add(Map<String, dynamic> recipe, String date) async {
    final ok = await _change({
      'operation': 'add',
      'id': newShoppingItemId(),
      'kind': 'recipe',
      'recipe_id': '${recipe['id']}',
      'date': date,
    });
    if (ok && mounted) await _pairings('${recipe['id']}', date);
  }

  Future<void> _pairings(String recipeId, String date) async {
    if (!_ready) return;
    final epoch = _accessEpoch;
    try {
      final data = await widget.request('$_path/pairings/$recipeId');
      if (!mounted || !_usable(epoch)) return;
      final existing = _entries
          .where((e) => e['plan_date'] == date)
          .map((e) => '${e['recipe_id']}')
          .toSet();
      final suggestions = recipeRows(data['recipes'])
          .where((r) => !existing.contains('${r['id']}'))
          .toList();
      if (suggestions.isEmpty) return;
      final selected = <String>{};
      final add = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Frequently made together'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final recipe in suggestions)
                      CheckboxListTile(
                        secondary: SizedBox(
                          width: 48,
                          height: 48,
                          child: RecipePhoto(
                            url: recipe['photo_url'] as String?,
                          ),
                        ),
                        title: Text('${recipe['title']}'),
                        value: selected.contains('${recipe['id']}'),
                        onChanged: (value) => update(() {
                          if (value == true) {
                            selected.add('${recipe['id']}');
                          } else {
                            selected.remove('${recipe['id']}');
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Add selected'),
              ),
            ],
          ),
        ),
      );
      if (add != true || !_usable(epoch)) return;
      // Confirm once for the whole suggestion selection on a past date.
      final past = _past(date);
      if (past && !await _confirmPast()) return;
      for (final id in selected) {
        if (!_usable(epoch)) break;
        final ok = await _change({
          'operation': 'add',
          'id': newShoppingItemId(),
          'kind': 'recipe',
          'recipe_id': id,
          'date': date,
        }, confirmed: past);
        if (!ok) break;
      }
    } catch (error) {
      if (!mounted || !_usable(epoch)) return;
      if (_invalidateAccess(error)) return;
      if (mounted) {
        _message('Could not load paired dishes. Your meal was added.');
      }
    }
  }

  Future<void> _pick(String date) async {
    if (!_ready) return;
    final epoch = _accessEpoch;
    final selection = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in [
              ('recipe', 'Recipe', Icons.menu_book_outlined),
              ('leftovers', 'Leftovers', Icons.kitchen_outlined),
              ('restaurant', 'Restaurant outing', Icons.restaurant_outlined),
            ])
              ListTile(
                leading: Icon(item.$3),
                title: Text(item.$2),
                onTap: () => Navigator.pop(context, item.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted || !_usable(epoch) || selection == null) return;
    if (selection != 'recipe') {
      await _change({
        'operation': 'add',
        'id': newShoppingItemId(),
        'kind': selection,
        'date': date,
      });
      return;
    }
    final recipe = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => RecipeBrowser(
          householdId: widget.householdId,
          householdName: widget.householdName,
          request: widget.request,
          mealPlanDestination: MaterialLocalizations.of(context)
              .formatFullDate(DateTime.parse(date)),
          onSelect: (recipe) => Navigator.pop(context, recipe),
        ),
      ),
    );
    if (recipe != null && _usable(epoch)) await _add(recipe, date);
  }

  Future<void> _move(Map<String, dynamic> entry, String date) async {
    if (entry['plan_date'] == date) return;
    await _change({
      'operation': 'move',
      'id': entry['id'],
      'date': date,
      '_revision': entry['_revision'],
    }, oldDate: entry['plan_date'] as String?);
  }

  Future<void> _remove(Map<String, dynamic> entry) async {
    if (!_ready || _saving) return;
    await _change({
      'operation': 'remove',
      'id': entry['id'],
      '_revision': entry['_revision'],
    }, oldDate: entry['plan_date'] as String?);
  }

  Future<void> _ingredients() async {
    if (!_ready) return;
    final epoch = _accessEpoch;
    Future<List<ShoppingIngredient>> load(DateTime start, DateTime end) async {
      try {
        final result = await loadMealPlanIngredients(
          widget.request,
          _path,
          start,
          end,
        );
        if (!_usable(epoch)) throw StateError('Meal plan access changed.');
        return result;
      } catch (error) {
        _invalidateAccess(error);
        rethrow;
      }
    }

    try {
      var range = DateTimeRange(start: _today, end: DateTime(2199, 12, 31));
      final ingredients = await load(range.start, range.end);
      if (!mounted || !_usable(epoch)) return;
      await showRecipeShopping(
        context,
        householdId: widget.householdId,
        request: widget.request,
        save: widget.save,
        ingredients: ingredients,
        onChooseDates: (sheetContext) async {
          final selected = await showDateRangePicker(
            context: sheetContext,
            firstDate: _today,
            lastDate: DateTime(2199, 12, 31),
            initialDateRange: DateTimeRange(
              start: range.start,
              end: range.end.year == 2199 ? _day(6) : range.end,
            ),
            helpText: 'Meal ingredients',
            saveText: 'Apply',
          );
          if (selected == null) return null;
          if (!_usable(epoch)) return null;
          try {
            final result = await load(selected.start, selected.end);
            range = selected;
            return result;
          } catch (_) {
            if (!_usable(epoch) && sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            rethrow;
          }
        },
      );
    } catch (error) {
      if (!_usable(epoch)) return;
      _message(
        error is ApiException
            ? error.message
            : 'Could not load meal ingredients.',
      );
    }
  }

  void _trackPointer(PointerEvent event) {
    if (event is PointerDownEvent) _pressedPointers.add(event.pointer);
    if (event is PointerMoveEvent && event.pointer == _dragPointer) {
      _dragPosition = event.position;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pressedPointers.remove(event.pointer);
      if (event.pointer == _dragPointer) _stopDragScroll();
    }
  }

  void _stopDragScroll() {
    _dragScroll?.cancel();
    _dragScroll = null;
    _dragPosition = null;
    _dragPointer = null;
  }

  void _autoScroll(DragUpdateDetails details) {
    if (!widget.active ||
        _background ||
        _pressedPointers.isEmpty ||
        !(_route?.isCurrent ?? true)) {
      return;
    }
    _dragPointer ??= _pressedPointers.last;
    _dragPosition = details.globalPosition;
    _dragScroll ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!mounted ||
          !widget.active ||
          _background ||
          !_ready ||
          !(_route?.isCurrent ?? true) ||
          !_pressedPointers.contains(_dragPointer)) {
        _stopDragScroll();
        return;
      }
      final box = _scrollArea.currentContext?.findRenderObject() as RenderBox?;
      final toolbar = _toolbar.currentContext?.findRenderObject() as RenderBox?;
      final position = _dragPosition;
      if (box == null ||
          toolbar == null ||
          position == null ||
          !_scroll.hasClients) {
        return;
      }
      final point = box.globalToLocal(position);
      final barPoint = toolbar.globalToLocal(position);
      if (point.dx < 0 ||
          point.dx > box.size.width ||
          position.dy < 0 ||
          point.dy > box.size.height + 24) {
        return;
      }
      final up =
          barPoint.dy <= toolbar.size.height &&
          barPoint.dx >= toolbar.size.width / 3 &&
          barPoint.dx <= toolbar.size.width;
      final edge = (box.size.height / 3).clamp(40.0, 120.0);
      final down = point.dy > box.size.height - edge;
      final direction = up
          ? -1
          : down
          ? 1
          : 0;
      if (direction == 0) return;
      final speed = up
          ? 18.0
          : 6 + 18 * (1 - (box.size.height - point.dy).clamp(0, edge) / edge);
      _scroll.jumpTo(
        (_scroll.offset + direction * speed).clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  Widget _tile(Map<String, dynamic> entry) {
    final card = SizedBox(
      width: 145,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: entry['kind'] == 'recipe' && entry['available'] == true
                  ? () =>
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecipeDetail(
                              householdId: widget.householdId,
                              recipeId: '${entry['recipe_id']}',
                              title: '${entry['title']}',
                              request: widget.request,
                              save: widget.save,
                            ),
                          ),
                        ).then((_) {
                          if (mounted) {
                            _load(quiet: true);
                          }
                        })
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 84,
                    child: entry['kind'] == 'recipe'
                        ? RecipePhoto(url: entry['photo_url'] as String?)
                        : ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Icon(
                              entry['kind'] == 'leftovers'
                                  ? Icons.kitchen_outlined
                                  : Icons.restaurant_outlined,
                              size: 32,
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    child: Text(
                      '${entry['title']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return LongPressDraggable<Map<String, dynamic>>(
      data: {'entry': entry},
      maxSimultaneousDrags: _saving ? 0 : 1,
      onDragUpdate: _autoScroll,
      onDragEnd: (_) => _stopDragScroll(),
      feedback: Material(color: Colors.transparent, child: card),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: card,
    );
  }

  Widget _dateSection(String date) {
    final entries = _entries.where((e) => e['plan_date'] == date).toList();
    final today = date == mealPlanDate(_today);
    final past = _past(date);
    final colors = Theme.of(context).colorScheme;
    final label = MaterialLocalizations.of(context)
        .formatMediumDate(DateTime.parse(date));
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (_) => !_saving,
      onAcceptWithDetails: (details) {
        final entry = details.data['entry'];
        if (entry is Map<String, dynamic>) {
          _move(entry, date);
        } else {
          _add(Map<String, dynamic>.from(details.data['recipe'] as Map), date);
        }
      },
      builder: (context, candidates, rejected) => Container(
        key: ValueKey('meal-day-$date'),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? colors.primaryContainer
              : past
              ? colors.onSurface.withValues(alpha: .12)
              : Colors.transparent,
          border: today
              ? Border(left: BorderSide(color: colors.primary, width: 3))
              : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(color: today ? colors.primary : null),
                      ),
                      if (today)
                        Chip(
                          label: Text(
                            'Today',
                            style: TextStyle(color: colors.onPrimary),
                          ),
                          backgroundColor: colors.primary,
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _pick(date),
                  child: const Text('+ Add'),
                ),
              ],
            ),
            if (entries.isNotEmpty)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: entries.map(_tile).toList(),
              )
            else
              const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _fetching ? null : () => _load(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    final list = Column(
      children: [
        SizedBox(
          key: _toolbar,
          height: 80,
          child: Row(
            children: [
              Expanded(
                child: DragTarget<Map<String, dynamic>>(
                  key: const ValueKey('meal-trash'),
                  onWillAcceptWithDetails: (details) =>
                      !_saving && details.data['entry'] is Map<String, dynamic>,
                  onAcceptWithDetails: (details) {
                    _stopDragScroll();
                    _remove(details.data['entry'] as Map<String, dynamic>);
                  },
                  builder: (context, candidates, rejected) => Tooltip(
                    message: 'Drag a meal here to delete',
                    child: Container(
                      height: 80,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 28),
                      decoration: BoxDecoration(
                        color: candidates.isEmpty
                            ? Colors.transparent
                            : Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _scroll.hasClients
                          ? _scroll.animateTo(
                              0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            )
                          : null,
                      child: const Text('Today'),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _ingredients,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Ingredients'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: Text(_error!)),
                TextButton(
                  onPressed: () => _load(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        if (_saving) const LinearProgressIndicator(),
        Expanded(
          child: _loading && _entries.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(
                  key: _scrollArea,
                  controller: _scroll,
                  center: _center,
                  anchor: .30,
                  slivers: [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, index) =>
                            _dateSection(mealPlanDate(_day(-index - 1))),
                        childCount: _pastDays,
                      ),
                    ),
                    SliverList(
                      key: _center,
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _dateSection(mealPlanDate(_day(index))),
                        childCount: _futureDays + 1,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 950
          ? list
          : Row(
              children: [
                Expanded(child: list),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 340,
                  child: RecipeBrowser(
                    householdId: widget.householdId,
                    householdName: widget.householdName,
                    request: widget.request,
                    embedded: true,
                    dragRecipes: true,
                    onRecipeDragUpdate: _autoScroll,
                    onRecipeDragEnd: _stopDragScroll,
                    mealPlanToday: _today,
                    onSelect: (recipe) =>
                        _add(recipe, recipe['_meal_date'] as String),
                  ),
                ),
              ],
            ),
    );
  }
}
