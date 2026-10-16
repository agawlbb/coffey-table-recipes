import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeTimers {
  static const channel = MethodChannel('coffey_table_recipes/timers');
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static Future<List<Map<String, dynamic>>> restore() async {
    if (!supported) return [];
    final rows = await channel.invokeListMethod<dynamic>('list') ?? [];
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
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
    }
  }

  static Future<void> cancel(String key) async {
    if (supported) await channel.invokeMethod<void>('cancel', {'key': key});
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
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await NativeTimers.channel
          .invokeMapMethod<String, dynamic>('settings');
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Timer settings are unavailable on this device.',
        );
      }
    }
  }

  Future<void> _choose(String tone) async {
    try {
      await NativeTimers.channel.invokeMethod<void>('setTone', {'tone': tone});
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the timer tone.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final android = defaultTargetPlatform == TargetPlatform.android;
    final tones =
        (_settings?['tones'] as List?) ??
        [
          {'value': '', 'label': 'Default alarm'},
          if (!android) ...[
            {'value': 'gentle.wav', 'label': 'Gentle chime'},
            {'value': 'bright.wav', 'label': 'Bright bell'},
          ],
        ];
    return Scaffold(
      appBar: AppBar(title: const Text('Timer settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) Text(_error!),
          if (_settings != null) ...[
            Text(_settings!['mode'] as String),
            const SizedBox(height: 16),
            const Text('Alarm tone (applies to new or edited timers)'),
            for (final tone in tones)
              ListTile(
                title: Text(tone['label'] as String),
                leading: Icon(
                  _settings!['tone'] == tone['value']
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: () => _choose(tone['value'] as String),
              ),
          ] else if (_error == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
