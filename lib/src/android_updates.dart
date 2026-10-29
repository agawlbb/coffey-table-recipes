import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const androidDownloadUrl =
    'https://vps.coffeybean.com/recipes/android/latest.apk';
const androidReleaseUrl =
    'https://vps.coffeybean.com/recipes/android/latest.json';

/// Checks are independent of sign-in and notification permission.
class AndroidUpdateHost extends StatefulWidget {
  const AndroidUpdateHost({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.enabled,
    this.fetchRelease,
    this.installedBuild,
    this.registerPush,
    this.openDownload,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final bool? enabled;
  final Future<Map<String, dynamic>> Function()? fetchRelease;
  final Future<int> Function()? installedBuild;
  final Future<void> Function()? registerPush;
  final Future<bool> Function()? openDownload;

  @override
  State<AndroidUpdateHost> createState() => _AndroidUpdateHostState();
}

class _AndroidUpdateHostState extends State<AndroidUpdateHost>
    with WidgetsBindingObserver {
  bool _checking = false;
  bool _dialogOpen = false;
  bool _registered = false;
  bool get _enabled =>
      widget.enabled ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _register() async {
    if (_registered) return;
    try {
      if (widget.registerPush != null) {
        await widget.registerPush!();
      } else {
        await FirebaseMessaging.instance.requestPermission();
        await FirebaseMessaging.instance.subscribeToTopic('android_releases');
      }
      _registered = true;
    } catch (_) {
      // Firebase or networking may be unavailable; retry on the next opening.
    }
  }

  Future<Map<String, dynamic>> _fetch() async {
    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.parse(androidReleaseUrl),
            headers: {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw StateError('Release unavailable');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<void> _check() async {
    if (!mounted || !_enabled || _checking || _dialogOpen) return;
    _checking = true;
    unawaited(_register());
    try {
      final build =
          await (widget.installedBuild?.call() ??
              PackageInfo.fromPlatform().then(
                (info) => int.parse(info.buildNumber),
              ));
      final release = await (widget.fetchRelease?.call() ?? _fetch());
      final latest = release['build'];
      final version = release['version'];
      if (latest is! int ||
          latest <= build ||
          version is! String ||
          !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
          release['url'] != androidDownloadUrl ||
          !mounted ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        return;
      }
      final context = widget.navigatorKey.currentState?.overlay?.context;
      if (context == null || !context.mounted) return;
      _dialogOpen = true;
      await showDialog<void>(
        context: context,
        builder: (_) => _UpdateDialog(
          version: version,
          openDownload:
              widget.openDownload ??
              () => launchUrl(
                Uri.parse(androidDownloadUrl),
                mode: LaunchMode.externalApplication,
              ),
        ),
      );
    } catch (_) {
      // Offline or invalid metadata must never prevent use of the app.
    } finally {
      _checking = false;
      _dialogOpen = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.version, required this.openDownload});
  final String version;
  final Future<bool> Function() openDownload;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _opening = false;
  bool _failed = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Android update available'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version ${widget.version} is available. Download the APK to update Coffey Table Recipes.',
          ),
          const SizedBox(height: 12),
          const SelectableText(androidDownloadUrl),
          if (_failed)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Could not open the download. Try again or copy the link into your browser.',
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Later'),
      ),
      FilledButton(
        onPressed: _opening
            ? null
            : () async {
                setState(() {
                  _opening = true;
                  _failed = false;
                });
                bool opened;
                try {
                  opened = await widget.openDownload();
                } catch (_) {
                  opened = false;
                }
                if (!mounted) return;
                setState(() {
                  _opening = false;
                  _failed = !opened;
                });
              },
        child: const Text('Download update'),
      ),
    ],
  );
}
