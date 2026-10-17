import 'dart:async';

import 'package:flutter/material.dart';

import 'native_timers.dart';
import 'recipe_time.dart';

String timerCountdown(Map<String, dynamic> timer, DateTime now) {
  final deadline = DateTime.fromMillisecondsSinceEpoch(
    (timer['deadline'] as num).toInt(),
  );
  final seconds = (deadline.difference(now).inMilliseconds / 1000).ceil();
  return seconds <= 0 ? 'Time is up' : formatRecipeTime(seconds, clock: true);
}

/// Keeps native timers visible independently of the current page or recipe.
class ActiveTimerHost extends StatefulWidget {
  const ActiveTimerHost({
    super.key,
    required this.child,
    required this.navigatorKey,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  @override
  State<ActiveTimerHost> createState() => _ActiveTimerHostState();
}

class _ActiveTimerHostState extends State<ActiveTimerHost>
    with WidgetsBindingObserver {
  Timer? _ticker;
  bool _refreshing = false;
  bool _foreground = true;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    if (NativeTimers.supported) {
      WidgetsBinding.instance.addObserver(this);
      NativeTimers.active.addListener(_changed);
      unawaited(_refresh());
      _changed();
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await NativeTimers.restore();
    } catch (_) {
      // Keep the last confirmed timers when a platform read fails.
    } finally {
      _refreshing = false;
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_foreground && NativeTimers.active.value.isNotEmpty) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
        if (++_ticks % 10 == 0) unawaited(_refresh());
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_refresh());
    _changed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NativeTimers.active.removeListener(_changed);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timers = [...NativeTimers.active.value]
      ..sort((a, b) => (a['deadline'] as num).compareTo(b['deadline'] as num));
    if (!NativeTimers.supported || timers.isEmpty) return widget.child;
    final theme = Theme.of(context);
    return Column(
      children: [
        Material(
          color: theme.colorScheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.timer_outlined),
              title: Text(
                timers.length == 1
                    ? '${timers.first['title'] ?? 'Cooking timer'}'
                    : '${timers.length} cooking timers',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${timerCountdown(timers.first, DateTime.now())}'),
              trailing: const Icon(Icons.expand_more),
              onTap: () => showModalBottomSheet<void>(
                context: widget.navigatorKey.currentState!.overlay!.context,
                useSafeArea: true,
                isScrollControlled: true,
                showDragHandle: true,
                constraints: const BoxConstraints(maxWidth: 640),
                builder: (_) => const RunningTimersSheet(),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class RunningTimersSheet extends StatefulWidget {
  const RunningTimersSheet({super.key});
  @override
  State<RunningTimersSheet> createState() => _RunningTimersSheetState();
}

class _RunningTimersSheetState extends State<RunningTimersSheet> {
  Timer? _ticker;
  final Set<String> _busy = {};
  String? _error;
  @override
  void initState() {
    super.initState();
    NativeTimers.active.addListener(_changed);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    NativeTimers.active.removeListener(_changed);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _stop(String key) async {
    setState(() {
      _busy.add(key);
      _error = null;
    });
    try {
      await NativeTimers.cancel(key);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not stop this timer. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = [...NativeTimers.active.value]
      ..sort((a, b) => (a['deadline'] as num).compareTo(b['deadline'] as num));
    return FractionallySizedBox(
      heightFactor: .6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              'Cooking timers',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(liveRegion: true, child: Text(_error!)),
            ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No running timers'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      final key = row['key'] as String;
                      return ListTile(
                        leading: const Icon(Icons.timer_outlined),
                        title: Text('${row['title'] ?? 'Cooking timer'}'),
                        subtitle: Text(timerCountdown(row, DateTime.now())),
                        trailing: TextButton(
                          onPressed: _busy.contains(key)
                              ? null
                              : () => _stop(key),
                          child: const Text('Stop'),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
