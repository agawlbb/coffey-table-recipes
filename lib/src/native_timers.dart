import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeTimers {
  static const channel = MethodChannel('coffey_table_recipes/timers');
  static final active = ValueNotifier<List<Map<String, dynamic>>>([]);
  static int _revision = 0;
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static Future<List<Map<String, dynamic>>> restore() async {
    if (!supported) return [];
    final revision = _revision;
    final rows = await channel.invokeListMethod<dynamic>('list') ?? [];
    if (revision != _revision) return active.value;
    final timers = rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    active.value = timers;
    return timers;
  }

  static Future<void> schedule(
    String key,
    DateTime deadline,
    String title,
  ) async {
    if (supported) {
      await channel.invokeMethod<void>('schedule', {
        'key': key,
        'deadline': deadline.millisecondsSinceEpoch,
        'title': title,
      });
      _revision++;
      active.value = [
        ...active.value.where((row) => row['key'] != key),
        {
          'key': key,
          'deadline': deadline.millisecondsSinceEpoch,
          'title': title,
        },
      ];
    }
  }

  static Future<void> cancel(String key) async {
    if (supported) {
      await channel.invokeMethod<void>('cancel', {'key': key});
      _revision++;
      active.value = active.value.where((row) => row['key'] != key).toList();
    }
  }
}

class TimerSettings extends StatefulWidget {
  const TimerSettings({super.key});
  @override
  State<TimerSettings> createState() => _TimerSettingsState();
}

class _TimerSettingsState extends State<TimerSettings> {
  Map<String, dynamic>? _settings;
  String? _error;
  bool _saving = false;

  List<Map<String, dynamic>> get _tones =>
      (_settings?['tones'] as List? ??
              [
                {'value': '', 'label': 'Default alarm'},
                if (defaultTargetPlatform != TargetPlatform.android) ...[
                  {'value': 'gentle.wav', 'label': 'Gentle chime'},
                  {'value': 'bright.wav', 'label': 'Bright bell'},
                ],
              ])
          .map((tone) => Map<String, dynamic>.from(tone as Map))
          .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final settings = await NativeTimers.channel
          .invokeMapMethod<String, dynamic>('settings');
      if (settings == null) throw StateError('No timer settings');
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Timer settings are unavailable. Please try again.',
        );
      }
    }
  }

  Future<void> _choose() async {
    final tones = _tones;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => AlarmTonePicker(
        tones: tones,
        selected: _settings!['tone'] as String? ?? '',
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await NativeTimers.channel.invokeMethod<void>('setTone', {
        'tone': selected,
      });
      if (mounted) {
        setState(() => _settings = {..._settings!, 'tone': selected});
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save the alarm tone. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = _tones;
    final selected = tones
        .where((tone) => tone['value'] == _settings?['tone'])
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Timer settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Cooking timers', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Choose the sound for your cooking reminders.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  if (_settings == null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                if (_settings != null) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      leading: Icon(
                        Icons.music_note_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: const Text('Alarm tone'),
                      subtitle: Text(
                        selected?['label'] as String? ?? 'Default alarm',
                      ),
                      trailing: _saving
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _saving ? null : _choose,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Text(
                      'Applies to new or edited timers. Running timers keep their current sound.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(Icons.info_outline),
                    title: const Text('How timers work'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Text(
                        _settings!['mode'] as String? ?? '',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ] else if (_error == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Changes stay local to the sheet until Save is pressed.
class AlarmTonePicker extends StatefulWidget {
  const AlarmTonePicker({
    super.key,
    required this.tones,
    required this.selected,
  });
  final List<Map<String, dynamic>> tones;
  final String selected;
  @override
  State<AlarmTonePicker> createState() => _AlarmTonePickerState();
}

class _AlarmTonePickerState extends State<AlarmTonePicker>
    with WidgetsBindingObserver {
  late String _selected = widget.selected;
  String _query = '';
  String? _previewError;
  int _previewGeneration = 0;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _stopPreview() {
    _previewGeneration++;
    _previewTimer?.cancel();
    unawaited(
      NativeTimers.channel
          .invokeMethod<void>('stopPreview')
          .catchError((Object _) {}),
    );
  }

  Future<void> _play(String tone) async {
    _stopPreview();
    final generation = _previewGeneration;
    setState(() {
      _previewError = null;
    });
    try {
      await NativeTimers.channel.invokeMethod<void>('previewTone', {
        'tone': tone,
      });
      if (!mounted || generation != _previewGeneration) return;
      _previewTimer = Timer(const Duration(seconds: 1), _stopPreview);
    } catch (_) {
      if (mounted && generation == _previewGeneration) {
        setState(() {
          _previewError =
              'Could not play this sound. Check your volume and try again.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopPreview();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewTimer?.cancel();
    _previewGeneration++;
    unawaited(
      NativeTimers.channel
          .invokeMethod<void>('stopPreview')
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = widget.tones
        .where(
          (tone) => (tone['label'] as String).toLowerCase().contains(_query),
        )
        .toList();
    return FractionallySizedBox(
      heightFactor: .85,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text('Alarm tone', style: theme.textTheme.headlineSmall),
            ),
            if (widget.tones.length > 8)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search sounds',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
            const Divider(height: 1),
            if (_previewError != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _previewError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            Expanded(
              child: tones.isEmpty
                  ? const Center(child: Text('No sounds found'))
                  : RadioGroup<String>(
                      groupValue: _selected,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selected = value);
                          unawaited(_play(value));
                        }
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: tones.length,
                        itemBuilder: (_, index) => RadioListTile<String>(
                          value: tones[index]['value'] as String,
                          title: Text(tones[index]['label'] as String),
                          selected: tones[index]['value'] == _selected,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                      ),
                    ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
