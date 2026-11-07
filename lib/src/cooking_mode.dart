import 'combined_cooking.dart';
import 'connection_indicator.dart';
import 'cooking_sessions.dart';
import 'cooking_session_ui.dart';
import 'child_mode.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'recipe_time.dart';
import 'recipe_menu.dart';
import 'native_timers.dart';

import 'package:flutter/services.dart';

import 'recipe_value.dart';

class CookingMode extends StatefulWidget {
  const CookingMode({
    super.key,
    required this.recipe,
    this.now = DateTime.now,
    this.menuBuilder,
    this.sessionId,
    this.sessions,
  });
  final Map<String, dynamic> recipe;
  final WidgetBuilder? menuBuilder;
  final String? sessionId;
  final CookingSessions? sessions;
  final DateTime Function() now;
  @override
  State<CookingMode> createState() => _CookingModeState();
}

class _CookingModeState extends State<CookingMode>
    with WidgetsBindingObserver, RouteAware {
  static _CookingModeState? _wakeOwner;
  final Set<String> _completed = {};
  final Map<String, GlobalKey> _stepKeys = {};
  CookingSessions get _sessions => widget.sessions ?? cookingSessions;
  PageRoute<dynamic>? _route;
  bool _positioned = false,
      _routeVisible = true,
      _stepBusy = false,
      _closing = false;
  Map<String, dynamic>? get _session =>
      widget.sessionId == null ? null : _sessions.session(widget.sessionId!);
  void _sessionChanged() {
    if (!mounted || widget.sessionId == null) return;
    final s = _session;
    if (s == null) {
      if (_closing) return;
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _route != null) {
          if (_routeVisible) {
            final openBrowser = cookingRecipeBrowser;
            if (openBrowser != null) {
              openBrowser();
            } else {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          } else {
            Navigator.of(context).removeRoute(_route!);
          }
        }
      });
      // Session notifications can arrive with no animation or pending frame.
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    setState(() {
      _completed
        ..clear()
        ..addAll((s['completed'] as List? ?? []).map((e) => '$e'));
      _timers.clear();
      for (final timer in _sessions.timers(widget.sessionId!)) {
        if (timer['cancelled'] != true) {
          _timers['${timer['action_id']}'] = widget.now().add(
            Duration(
              milliseconds:
                  (timer['deadline_ms'] as num).toInt() -
                  _sessions.now.millisecondsSinceEpoch,
            ),
          );
        }
      }
    });
    _tick();
    if (!_positioned) {
      _positioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final first = _rows('steps')
            .where((s) => !_completed.contains('${s['id']}'))
            .firstOrNull;
        final target = first == null
            ? _endKey.currentContext
            : _stepKeys['${first['id']}']?.currentContext;
        if (target != null) Scrollable.ensureVisible(target, alignment: 0);
      });
    }
  }

  final _endKey = GlobalKey();
  void _presence(bool open) {
    if (widget.sessionId != null) {
      unawaited(
        _sessions.presence(widget.sessionId!, open).catchError((Object _) {}),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      cookingRouteObserver.unsubscribe(this);
      _route = route;
      cookingRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() {
    _routeVisible = true;
    _presence(true);
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _presence(true);
    _syncWake();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _presence(false);
    _syncWake();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _presence(false);
  }

  Future<void> _check(String step, bool checked) async {
    if (_stepBusy) return;
    if (widget.sessionId == null) {
      setState(() {
        if (checked) {
          _completed.add(step);
        } else {
          _completed.remove(step);
        }
      });
      return;
    }
    _stepBusy = true;
    try {
      await _sessions.check(widget.sessionId!, step, checked);
    } catch (e) {
      if (mounted) cookingError(context, e);
      await _sessions.refresh();
    } finally {
      _stepBusy = false;
    }
  }

  Future<void> _end() async {
    if (widget.sessionId == null) {
      Navigator.pop(context);
      return;
    }
    if (_sessions
        .timers(widget.sessionId!)
        .any(
          (t) =>
              t['cancelled'] != true &&
              (t['deadline_ms'] as num) > _sessions.now.millisecondsSinceEpoch,
        )) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('End session and cancel timers?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep cooking'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('End session'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await _sessions.end(widget.sessionId!);
    } catch (e) {
      if (mounted) cookingError(context, e);
    }
  }

  final Map<String, DateTime> _timers = {};
  Timer? _ticker;
  bool _keepAwake = true;
  bool _foreground = true;
  Future<void> _wakeQueue = Future.value();

  List<Map<String, dynamic>> _rows(String key) =>
      List<Map<String, dynamic>>.from(
        (_session?['recipe'] as Map? ?? widget.recipe)[key] as List? ?? [],
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (NativeTimers.supported) {
      NativeTimers.active.addListener(_nativeTimersChanged);
    }
    _syncWake();
    if (widget.sessionId != null) {
      _sessions.addListener(_sessionChanged);
      _sessionChanged();
    } else {
      _restoreTimers();
    }
  }

  void _syncWake() {
    _wakeQueue = _wakeQueue.then((_) async {
      final enable = mounted && _keepAwake && _foreground && _routeVisible;
      if (enable) {
        _wakeOwner = this;
      } else if (_wakeOwner != this) {
        return;
      } else {
        _wakeOwner = null;
      }
      try {
        await WakelockPlus.toggle(enable: enable);
      } catch (_) {
        // Some platforms do not support keeping the screen awake.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && widget.sessionId == null) _restoreTimers();
    _syncWake();
  }

  @override
  void dispose() {
    cookingRouteObserver.unsubscribe(this);
    _sessions.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    NativeTimers.active.removeListener(_nativeTimersChanged);
    _ticker?.cancel();
    // Queue release after any in-flight enable request.
    _wakeQueue
        .then((_) async {
          if (_wakeOwner == this) {
            _wakeOwner = null;
            await WakelockPlus.disable();
          }
        })
        .catchError((Object _) {});
    super.dispose();
  }

  String _remaining(DateTime deadline) {
    final seconds = (deadline.difference(widget.now()).inMilliseconds / 1000)
        .ceil();
    if (seconds <= 0) return 'Time is up';
    return formatRecipeTime(seconds, clock: true);
  }

  String _timerKey(String id) => widget.sessionId == null
      ? '${widget.recipe['id']}:$id'
      : 'remote:session:${widget.sessionId}:$id';
  void _tick() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _timers.isNotEmpty) setState(() {});
    });
  }

  void _nativeTimersChanged() {
    if (!mounted) return;
    if (widget.sessionId != null) {
      _sessionChanged();
      return;
    }
    final prefix = '${widget.recipe['id']}:';
    setState(() {
      _timers.clear();
      for (final row in NativeTimers.active.value) {
        final key = row['key'] as String;
        if (key.startsWith(prefix)) {
          _timers[key.substring(
            prefix.length,
          )] = DateTime.fromMillisecondsSinceEpoch(
            (row['deadline'] as num).toInt(),
          );
        }
      }
    });
    _tick();
  }

  Future<void> _restoreTimers() async {
    if (!NativeTimers.supported) return;
    try {
      final rows = await NativeTimers.restore();
      if (!mounted) return;
      final prefix = '${widget.recipe['id']}:';
      setState(() {
        _timers.clear();
        for (final row in rows) {
          final key = row['key'] as String;
          if (key.startsWith(prefix)) {
            _timers[key.substring(
              prefix.length,
            )] = DateTime.fromMillisecondsSinceEpoch(
              (row['deadline'] as num).toInt(),
            );
          }
        }
      });
      _tick();
    } catch (_) {
      /* A platform failure must not erase a displayed timer. */
    }
  }

  Future<void> _timer(String id, int seconds) async {
    if (_timerBusy) return;
    _timerBusy = true;
    try {
      if (_timers.containsKey(id)) {
        final sessionTimer = widget.sessionId == null
            ? null
            : _sessions
                  .timers(widget.sessionId!)
                  .where((t) => '${t['action_id']}' == id)
                  .firstOrNull;
        final running =
            NativeTimers.active.value
                .where((r) => r['key'] == _timerKey(id))
                .firstOrNull ??
            {
              'deadline': _timers[id]!.millisecondsSinceEpoch,
              'extension_seconds': sessionTimer?['extension_seconds'] ?? 0,
            };
        final extension = NativeTimers.remainingExtension(
          running,
          now: widget.now(),
        );
        final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cooking timer'),
            content: Text(_remaining(_timers[id]!)),
            actions: [
              if (extension > 0)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'extend'),
                  child: Text('Add ${formatRecipeTime(extension)}'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Keep timer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Cancel timer'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'edit'),
                child: const Text('Change timer'),
              ),
            ],
          ),
        );
        if (!mounted || action == null) return;
        if (action == 'extend') {
          if (widget.sessionId != null && !NativeTimers.supported) {
            await _sessions.change(widget.sessionId!, 'timer', {
              'action_id': id,
              'cancelled': false,
              'extend': true,
              'extension_seconds': 0,
              'deadline_ms': _sessions.now
                  .add(Duration(seconds: extension))
                  .millisecondsSinceEpoch,
              'revision': sessionTimer?['revision'] ?? 0,
            });
          } else {
            await NativeTimers.extend(_timerKey(id), now: widget.now());
          }
          if (widget.sessionId != null) {
            _sessionChanged();
          } else {
            await _restoreTimers();
          }
          return;
        }
        if (action == 'cancel') {
          if (widget.sessionId != null && !NativeTimers.supported) {
            await _sessions.change(widget.sessionId!, 'timer', {
              'action_id': id,
              'cancelled': true,
              'revision':
                  (_session?['timers'] as List? ?? [])
                      .where((t) => '${t['action_id']}' == id)
                      .firstOrNull?['revision'] ??
                  0,
            });
          } else {
            await NativeTimers.cancel(_timerKey(id));
          }
          if (mounted) setState(() => _timers.remove(id));
          return;
        }
        final controller = TextEditingController(
          text: (seconds / 60).toString(),
        );
        final changed = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Minutes from now'),
            content: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final minutes = double.tryParse(controller.text);
                  if (minutes != null &&
                      minutes.isFinite &&
                      minutes > 0 &&
                      minutes <= 10080) {
                    Navigator.pop(context, (minutes * 60).round());
                  }
                },
                child: const Text('Set timer'),
              ),
            ],
          ),
        );
        // Route transitions may still use the controller until the next frame.
        if (!mounted || changed == null) return;
        seconds = changed;
      }
      final deadline = widget.now().add(Duration(seconds: seconds));
      final recipeAction = _rows('actions')
          .where((a) => '${a['id']}' == id)
          .firstOrNull;
      final extra = recipeAction == null
          ? 0
          : (recipeSeconds(recipeAction['duration_max_seconds']) ?? seconds) -
                seconds;
      final extensionSeconds = _timers.containsKey(id) || extra < 0 ? 0 : extra;
      final actionLabel = _rows('actions')
          .where((action) => '${action['id']}' == id)
          .firstOrNull?['label'];
      if (widget.sessionId != null && !NativeTimers.supported) {
        await _sessions.change(widget.sessionId!, 'timer', {
          'action_id': id,
          'cancelled': false,
          'extension_seconds': extensionSeconds,
          'deadline_ms': _sessions.now
              .add(Duration(seconds: seconds))
              .millisecondsSinceEpoch,
          'revision':
              (_session?['timers'] as List? ?? [])
                  .where((t) => '${t['action_id']}' == id)
                  .firstOrNull?['revision'] ??
              0,
        });
      } else {
        await NativeTimers.schedule(
          _timerKey(id),
          deadline,
          '${widget.recipe['title'] ?? 'Cooking timer'}${actionLabel == null ? '' : ' · $actionLabel'}',
          extensionSeconds: extensionSeconds,
        );
      }
      if (mounted) setState(() => _timers[id] = deadline);
      _tick();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PlatformException
                  ? error.message ?? 'Could not start timer.'
                  : 'Could not start timer.',
            ),
          ),
        );
      }
    } finally {
      _timerBusy = false;
    }
  }

  bool _timerBusy = false;

  void _ingredients() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Ingredients',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            for (final groupId in [
              null,
              ..._rows('groups').map((g) => g['id']),
            ]) ...[
              if (groupId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _rows('groups')
                            .firstWhere((g) => g['id'] == groupId)['title']
                        as String,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              for (final ingredient in _rows(
                'ingredients',
              ).where((i) => i['group_id'] == groupId))
                Padding(
                  padding: EdgeInsets.only(
                    top: 10,
                    bottom: 10,
                    left: groupId == null ? 0 : 16,
                  ),
                  child: Text(
                    '• ${ingredient['original_text']}',
                    style: const TextStyle(fontSize: 20, height: 1.5),
                  ),
                ),
            ],
            if (_rows('ingredients').isEmpty)
              const Text('No ingredients recorded.'),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to cooking'),
            ),
          ],
        ),
      ),
    ),
  );

  String? _viewedStep() {
    for (final entry in _stepKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final y = box.localToGlobal(Offset.zero).dy;
        if (y + box.size.height > 200 &&
            y < MediaQuery.sizeOf(context).height - 100) {
          return entry.key;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    childModeOf(context);
    if (childMode.value) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Unavailable in child mode.')),
        ),
      );
    }
    final steps = _rows('steps');
    final actions = _rows('actions');
    final combined = _session?['combined'] == true;
    return Scaffold(
      drawer: (widget.menuBuilder ?? cookingMenuBuilder)?.call(context),
      appBar: AppBar(
        title: const Text('Cooking mode'),
        actions: [
          ConnectionIndicator(
            householdId: '${_session?['household_id'] ?? ''}',
          ),
        ],
        leadingWidth: (widget.menuBuilder ?? cookingMenuBuilder) == null
            ? null
            : 96,
        leading: (widget.menuBuilder ?? cookingMenuBuilder) == null
            ? null
            : const RecipeMenuLeading(),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _ingredients,
            icon: const Icon(Icons.list_alt),
            label: const Text('View ingredients'),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.recipe['title'] as String,
                  maxLines: combined ? 2 : null,
                  overflow: combined
                      ? TextOverflow.ellipsis
                      : TextOverflow.visible,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (combined) ...[
                  if (_session!['started_at'] == null)
                    FilledButton(
                      onPressed: () async {
                        try {
                          await _sessions.change(
                            widget.sessionId!,
                            'start',
                            {},
                          );
                        } catch (e) {
                          if (context.mounted) cookingError(context, e);
                        }
                      },
                      child: const Text('Start cooking'),
                    ),
                  if (_sessions.planStart(_session!)?.isBefore(_sessions.now) ==
                      true)
                    const Text('Start time has passed.'),
                ],
                if (combined)
                  Row(
                    children: [
                      Flexible(
                        child: Tooltip(
                          message: 'Dinner time',
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            icon: const Icon(Icons.schedule, size: 18),
                            label: Text(
                              TimeOfDay.fromDateTime(
                                DateTime.fromMillisecondsSinceEpoch(
                                  (_session!['dinner_at'] as num).toInt(),
                                ),
                              ).format(context),
                            ),
                            onPressed: () async {
                              final session = _session!;
                              final dinner =
                                  DateTime.fromMillisecondsSinceEpoch(
                                    (session['dinner_at'] as num).toInt(),
                                  );
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(dinner),
                              );
                              if (time == null) return;
                              try {
                                await _sessions.change(
                                  widget.sessionId!,
                                  'dinner',
                                  {
                                    'dinner_at': DateTime(
                                      dinner.year,
                                      dinner.month,
                                      dinner.day,
                                      time.hour,
                                      time.minute,
                                    ).millisecondsSinceEpoch,
                                  },
                                );
                              } catch (e) {
                                if (context.mounted) cookingError(context, e);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            const Expanded(child: Text('Keep awake')),
                            Switch(
                              value: _keepAwake,
                              onChanged: (value) {
                                setState(() => _keepAwake = value);
                                _syncWake();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (!combined) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Keep screen awake'),
                    value: _keepAwake,
                    onChanged: (value) {
                      setState(() {
                        _keepAwake = value;
                      });
                      _syncWake();
                    },
                  ),
                ],
                LinearProgressIndicator(
                  value: steps.isEmpty ? 0 : _completed.length / steps.length,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final step in steps)
                          Card(
                            key: _stepKeys.putIfAbsent(
                              '${step['id']}',
                              () => GlobalKey(),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(
                                      combined
                                          ? '${cookingPlanTime(context, _session!, (step['offset_seconds'] as num).toInt())} · ${step["dish_title"]}'
                                          : 'Step ${step['position']}${step['section_title']?.toString().trim().isNotEmpty == true ? ' · ${step['section_title']}' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    value: _completed.contains('${step['id']}'),
                                    onChanged: (value) =>
                                        _check('${step['id']}', value == true),
                                  ),
                                  Text(
                                    step['instruction'] as String,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      height: 1.6,
                                    ),
                                  ),
                                  for (final action in actions.where(
                                    (a) => a['step_id'] == step['id'],
                                  ))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child:
                                          action['duration_seconds'] != null &&
                                              (action['duration_seconds']
                                                      as num) >
                                                  0
                                          ? OutlinedButton.icon(
                                              onPressed: () => _timer(
                                                '${action['id']}',
                                                (action['duration_seconds']
                                                        as num)
                                                    .toInt(),
                                              ),
                                              icon: const Icon(
                                                Icons.timer_outlined,
                                              ),
                                              label: Text(
                                                _timers.containsKey(
                                                      '${action['id']}',
                                                    )
                                                    ? '${_remaining(_timers['${action['id']}']!)} · Cancel'
                                                    : '${action['label'] ?? 'Start timer'} · ${formatRecipeTimeRange(action)}',
                                              ),
                                            )
                                          : Text(
                                              '${action['label'] ?? 'Target'}${action['temperature_value'] != null ? ': ${recipeValue(action['temperature_value'])}°${action['temperature_unit']}' : ''}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (_completed.length == steps.length &&
                            steps.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'All steps completed. Enjoy your meal!',
                              style: TextStyle(fontSize: 22),
                            ),
                          ),
                        if (combined)
                          TextButton.icon(
                            onPressed: () => showCookingFeedback(
                              context,
                              _sessions,
                              widget.sessionId!,
                              _viewedStep(),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Provide feedback'),
                          ),
                        OutlinedButton(
                          key: _endKey,
                          onPressed: _end,
                          child: Text(
                            widget.sessionId == null
                                ? 'Exit cooking mode'
                                : 'End cooking session',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
