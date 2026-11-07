import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_progress.dart';
import 'api.dart';
import 'cooking_sessions.dart';
import 'cooking_session_ui.dart';
import 'native_timers.dart';

String cookingPlanTime(BuildContext context, Map session, int offsetSeconds) {
  final dinner = DateTime.fromMillisecondsSinceEpoch(
    (session['dinner_at'] as num).toInt(),
  );
  final time = DateTime.fromMillisecondsSinceEpoch(
    dinner.millisecondsSinceEpoch + offsetSeconds * 1000,
  );
  final clock = TimeOfDay.fromDateTime(time).format(context);
  if (time.year == dinner.year &&
      time.month == dinner.month &&
      time.day == dinner.day) {
    return clock;
  }
  return '${MaterialLocalizations.of(context).formatShortDate(time)} · $clock';
}

class DinnerTimeSetting extends StatefulWidget {
  const DinnerTimeSetting({super.key});
  static Future<TimeOfDay> load() async {
    final minutes =
        await SharedPreferencesAsync().getInt('default_dinner_minutes') ?? 1080;
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  @override
  State<DinnerTimeSetting> createState() => _DinnerTimeSettingState();
}

class _DinnerTimeSettingState extends State<DinnerTimeSetting> {
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  @override
  void initState() {
    super.initState();
    DinnerTimeSetting.load().then((time) {
      if (mounted) setState(() => _time = time);
    });
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.restaurant_outlined),
    title: const Text('Dinner time'),
    trailing: Text(_time.format(context)),
    onTap: () async {
      final time = await showTimePicker(context: context, initialTime: _time);
      if (time == null) return;
      await SharedPreferencesAsync().setInt(
        'default_dinner_minutes',
        time.hour * 60 + time.minute,
      );
      if (mounted) setState(() => _time = time);
    },
  );
}

Future<void> showCombinedCooking(
  BuildContext context,
  String household,
  String date,
  List<Map<String, dynamic>> entries,
) async {
  final dishes = entries
      .where((e) => e['kind'] == 'recipe' && e['available'] != false)
      .toList();
  if (dishes.isEmpty) return;
  final time = await DinnerTimeSetting.load();
  if (!context.mounted) return;
  final coordinator = CookingSessionsScope.of(context);
  final session = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (_) => SafeArea(
      top: false,
      child: _PlanSelector(
        household: household,
        date: date,
        dishes: dishes,
        time: time,
        sessions: coordinator,
      ),
    ),
  );
  if (session == null || !context.mounted) return;
  await offerStartAlarm(context, coordinator, session);
  if (context.mounted) {
    await openCookingSession(context, session, sessions: coordinator);
  }
}

class _PlanSelector extends StatefulWidget {
  const _PlanSelector({
    required this.household,
    required this.date,
    required this.dishes,
    required this.time,
    required this.sessions,
  });
  final String household, date;
  final List<Map<String, dynamic>> dishes;
  final TimeOfDay time;
  final CookingSessions sessions;
  @override
  State<_PlanSelector> createState() => _PlanSelectorState();
}

class _PlanSelectorState extends State<_PlanSelector> {
  late final _selected = widget.dishes.map((e) => '${e['id']}').toSet();
  late TimeOfDay _time = widget.time;
  String? _error;
  bool _busy = false;
  final _progress = AiRunProgress();
  String? _attempt;
  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final date = DateTime.parse(widget.date);
    final dinner = DateTime(
      date.year,
      date.month,
      date.day,
      _time.hour,
      _time.minute,
    );
    try {
      _attempt ??= CookingSessions.randomId();
      final response = await _progress.run(
        () => widget.sessions.planRequest(widget.household, {
          'session_id': _attempt,
          'date': widget.date,
          'entry_ids': _selected.toList(),
          'dinner_at': dinner.millisecondsSinceEpoch,
        }),
      );
      if (mounted) Navigator.pop(context, response['session']);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not create the plan. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cook together',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final dish in widget.dishes)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${dish['title']}'),
                      value: _selected.contains('${dish['id']}'),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _attempt = null;
                              if (value == true) {
                                _selected.add('${dish['id']}');
                              } else {
                                _selected.remove('${dish['id']}');
                              }
                            }),
                    ),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Dinner'),
              trailing: Text(_time.format(context)),
              onTap: _busy
                  ? null
                  : () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (time != null && mounted) {
                        setState(() {
                          _time = time;
                          _attempt = null;
                        });
                      }
                    },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            AiProgressText(_progress),
            FilledButton(
              onPressed: _busy || _selected.isEmpty ? null : _generate,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create plan'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> offerStartAlarm(
  BuildContext context,
  CookingSessions sessions,
  Map<String, dynamic> session,
) async {
  if (!NativeTimers.supported) return;
  final start = sessions.planStart(session);
  if (start == null || !start.isAfter(sessions.now)) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Start time has passed.')));
    return;
  }
  final set = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(
        'Set start alarm for ${formatStartAlarmTime(dialog, start)}?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Set alarm'),
        ),
      ],
    ),
  );
  if (set == true) {
    try {
      await sessions.setStartAlarm('${session['id']}');
    } catch (e) {
      if (context.mounted) cookingError(context, e);
    }
  }
}

Future<void> showCookingFeedback(
  BuildContext context,
  CookingSessions sessions,
  String sessionId,
  String? viewedStep,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 700),
  builder: (_) => SafeArea(
    top: false,
    child: _FeedbackChat(
      sessions: sessions,
      sessionId: sessionId,
      viewedStep: viewedStep,
    ),
  ),
);

class _FeedbackChat extends StatefulWidget {
  const _FeedbackChat({
    required this.sessions,
    required this.sessionId,
    this.viewedStep,
  });
  final CookingSessions sessions;
  final String sessionId;
  final String? viewedStep;
  @override
  State<_FeedbackChat> createState() => _FeedbackChatState();
}

class _FeedbackChatState extends State<_FeedbackChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _progress = AiRunProgress();
  List<Map<String, dynamic>> _messages = [];
  bool _busy = false;
  String? _error, _turn, _sent;
  @override
  void initState() {
    super.initState();
    _messages = widget.sessions.feedbackMessages(widget.sessionId);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final s = widget.sessions.session(widget.sessionId);
    if (s == null) return;
    setState(() => _busy = true);
    try {
      final response = await widget.sessions.planRequest(
        '${s['household_id']}',
        {'action': 'history', 'session_id': widget.sessionId},
      );
      if (mounted) {
        setState(
          () => _messages = (response['messages'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }
    } catch (_) {
      // Existing messages and the input stay available; sending reports connection errors.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (_sent != text) {
      _turn = CookingSessions.randomId();
      _sent = text;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = widget.sessions.session(widget.sessionId);
      if (session == null) throw StateError('Session ended.');
      final result = await _progress.run(
        () => widget.sessions.planRequest('${session['household_id']}', {
          'action': 'feedback',
          'session_id': widget.sessionId,
          'turn_id': _turn,
          'message': text,
          'viewed_step': widget.viewedStep,
        }),
      );
      if (!mounted) return;
      setState(() {
        _messages = (result['messages'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _input.clear();
        _turn = null;
        _sent = null;
        if (result['progress_changed'] == true) _error = 'Cooking progressed while AI replied. Send another message to adjust the latest plan.';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not send feedback. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cooking feedback',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                for (final message in _messages)
                  Align(
                    alignment: message['role'] == 'user'
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: message['role'] == 'user'
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText('${message['content']}'),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          AiProgressText(_progress),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_busy,
                  maxLength: 8000,
                  decoration: const InputDecoration(
                    hintText: 'Your feedback',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
