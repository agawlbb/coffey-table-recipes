import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cooking_sessions.dart';
import 'notification_preferences.dart';
import 'sync_notifications.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    this.preferences,
    this.saveInvitations,
  });
  final NotificationPreferences? preferences;
  final Future<void> Function(bool)? saveInvitations;
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  NotificationPreferences get preferences =>
      widget.preferences ?? notificationPreferences;
  bool _loaded = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      await preferences.read();
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Notification settings are unavailable.');
      }
    }
  }

  Future<void> _open([String? category]) async {
    try {
      await preferences.openSettings(category);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open phone notification settings.');
      }
    }
  }

  Future<void> _set(String category, bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (category == 'invitations') {
        await (widget.saveInvitations?.call(enabled) ??
            CookingSessionsScope.of(context)
                .setInvitationNotifications(enabled));
      }
      if (category == 'timers' && enabled) {
        await const MethodChannel('coffey_table_recipes/timers')
            .invokeMethod<void>('requestTimerPermissions', {'force': true});
      }
      await preferences.set(category, enabled);
      if (category == 'pendingSaves') {
        await SyncNotifications.replay();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PlatformException
              ? error.message ??
                    'Could not update notification settings. Please try again.'
              : 'Could not update notification settings. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          children: [
            if (_error != null)
              ListTile(
                title: Text(_error!),
                trailing: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Retry',
                ),
              ),
            if (!_loaded && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (_loaded) ...[
              ListTile(
                title: const Text('Phone notification settings'),
                subtitle: Text(preferences.allowed ? 'Allowed' : 'Not allowed'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _open(),
              ),
              const Divider(),
              for (final entry in {
                'invitations': 'Cooking invitations',
                'timers': 'Cooking timers',
                'pendingSaves': 'Pending saves',
                if (defaultTargetPlatform == TargetPlatform.android)
                  'updates': 'App updates',
              }.entries)
                ListTile(
                  title: Text(entry.value),
                  subtitle:
                      !preferences.allowed ||
                          preferences.blockedChannels.contains(entry.key)
                      ? const Text('Blocked in phone settings')
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (defaultTargetPlatform == TargetPlatform.android)
                        IconButton(
                          tooltip: '${entry.value} phone settings',
                          onPressed: () => _open(entry.key),
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      Semantics(
                        label: entry.value,
                        child: Switch(
                          value: preferences.values[entry.key] ?? true,
                          onChanged: _busy
                              ? null
                              : (value) => _set(entry.key, value),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
