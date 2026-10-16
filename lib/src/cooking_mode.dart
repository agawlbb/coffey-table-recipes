import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'recipe_time.dart';
import 'native_timers.dart';

import 'package:flutter/services.dart';

import 'recipe_value.dart';

class CookingMode extends StatefulWidget {
  const CookingMode({super.key, required this.recipe, this.now = DateTime.now});
  final Map<String, dynamic> recipe;
  final DateTime Function() now;
  @override
  State<CookingMode> createState() => _CookingModeState();
}

class _CookingModeState extends State<CookingMode> with WidgetsBindingObserver {
  final Set<String> _completed = {};
  final Map<String, DateTime> _timers = {};
  Timer? _ticker;
  bool _keepAwake = true;
  bool _awake = false;
  bool _foreground = true;
  Future<void> _wakeQueue = Future.value();

  List<Map<String, dynamic>> _rows(String key) =>
      List<Map<String, dynamic>>.from(widget.recipe[key] as List? ?? []);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncWake();
    _restoreTimers();
  }

  void _syncWake() {
    _wakeQueue = _wakeQueue.then((_) async {
      final enable = mounted && _keepAwake && _foreground;
      try {
        await WakelockPlus.toggle(enable: enable);
        final actual = enable && await WakelockPlus.enabled;
        if (mounted) {
          setState(() {
            _awake = actual;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _awake = false;
          });
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _restoreTimers();
    _syncWake();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    // Queue release after any in-flight enable request.
    _wakeQueue.then((_) => WakelockPlus.disable()).catchError((Object _) {});
    super.dispose();
  }

  String _remaining(DateTime deadline) {
    final seconds = (deadline.difference(widget.now()).inMilliseconds / 1000)
        .ceil();
    if (seconds <= 0) return 'Time is up';
    return formatRecipeTime(seconds, clock: true);
  }

  String _timerKey(String id) => '${widget.recipe['id']}:$id';
  void _tick() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _timers.isNotEmpty) setState(() {});
    });
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
        final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cooking timer'),
            content: Text(_remaining(_timers[id]!)),
            actions: [
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
        if (action == 'cancel') {
          await NativeTimers.cancel(_timerKey(id));
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
      await NativeTimers.schedule(
        _timerKey(id),
        deadline,
        '${widget.recipe['title'] ?? 'Cooking timer'}',
      );
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
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              for (final ingredient in _rows(
                'ingredients',
              ).where((i) => i['group_id'] == groupId))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
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

  @override
  Widget build(BuildContext context) {
    final steps = _rows('steps');
    final actions = _rows('actions');
    return Scaffold(
      appBar: AppBar(title: const Text('Cooking mode')),
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
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.recipe['title'] as String,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text('${_completed.length} of ${steps.length} steps completed'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: steps.isEmpty ? 0 : _completed.length / steps.length,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep screen awake'),
                subtitle: Text(
                  !_keepAwake
                      ? 'Off'
                      : _awake
                      ? 'Enabled while cooking'
                      : 'Unavailable here — check your screen timeout',
                ),
                value: _keepAwake,
                onChanged: (value) {
                  setState(() {
                    _keepAwake = value;
                  });
                  _syncWake();
                },
              ),
              Text(
                NativeTimers.supported
                    ? 'Timers use device alarms or notifications and are restored when you return. Check Timer settings for permissions and sound limitations.'
                    : 'Web timers work only while this page remains active; no background alarm is scheduled.',
              ),
              const SizedBox(height: 16),
              for (final step in steps)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            'Step ${step['position']}${step['section_title']?.toString().trim().isNotEmpty == true ? ' · ${step['section_title']}' : ''}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          value: _completed.contains('${step['id']}'),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _completed.add('${step['id']}');
                            } else {
                              _completed.remove('${step['id']}');
                            }
                          }),
                        ),
                        Text(
                          step['instruction'] as String,
                          style: const TextStyle(fontSize: 22, height: 1.6),
                        ),
                        for (final action in actions.where(
                          (a) => a['step_id'] == step['id'],
                        ))
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child:
                                action['duration_seconds'] != null &&
                                    (action['duration_seconds'] as num) > 0
                                ? OutlinedButton.icon(
                                    onPressed: () => _timer(
                                      '${action['id']}',
                                      (action['duration_seconds'] as num)
                                          .toInt(),
                                    ),
                                    icon: const Icon(Icons.timer_outlined),
                                    label: Text(
                                      _timers.containsKey('${action['id']}')
                                          ? '${_remaining(_timers['${action['id']}']!)} · Cancel'
                                          : '${action['label'] ?? 'Start timer'} · ${formatRecipeTime(action['duration_seconds'])}',
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
              if (_completed.length == steps.length && steps.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'All steps completed. Enjoy your meal!',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Exit cooking mode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
