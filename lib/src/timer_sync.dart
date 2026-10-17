import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'native_timers.dart';

final timerSync = TimerSync();

/// Pushes are applied natively, including when no Flutter engine is running.
/// This coordinator registers the installation and reconciles missed updates.
class TimerSync with WidgetsBindingObserver {
  TimerSync({
    SharedPreferencesAsync Function()? preferences,
    RecipeApi? api,
    String? Function()? currentUid,
    Future<String?> Function()? idToken,
    Future<String?> Function()? pushToken,
    Future<void> Function()? authorizeReceiving,
    Stream<String?> Function()? accountChanges,
    Stream<String> Function()? tokenChanges,
  }) : _preferences = preferences ?? SharedPreferencesAsync.new,
       _api = api ?? RecipeApi(baseUrl: apiBaseUrl),
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _idToken =
           idToken ??
           (() async => FirebaseAuth.instance.currentUser?.getIdToken()),
       _pushToken = pushToken ?? (() => FirebaseMessaging.instance.getToken()),
       _authorizeReceiving = authorizeReceiving ?? _authorize,
       _accountChanges =
           accountChanges ??
           (() => FirebaseAuth.instance.authStateChanges().map(
             (user) => user?.uid,
           )),
       _tokenChanges =
           tokenChanges ?? (() => FirebaseMessaging.instance.onTokenRefresh);

  final String? Function() _currentUid;
  final Future<String?> Function() _idToken;
  final Future<String?> Function() _pushToken;
  final Future<void> Function() _authorizeReceiving;
  final Stream<String?> Function() _accountChanges;
  final Stream<String> Function() _tokenChanges;
  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  Future<void> _storageTail = Future.value();

  Future<void> _storage(Future<void> Function() action) {
    final next = _storageTail.then((_) => action());
    _storageTail = next.catchError((Object _) {});
    return next;
  }

  static Future<void> _authorize() async {
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError(
        'Allow notifications in device settings, then try again.',
      );
    }
    await NativeTimers.channel.invokeMethod<void>('requestTimerPermissions');
  }

  final status = ValueNotifier<String?>(null);
  final receiving = ValueNotifier<bool>(false);
  final signedIn = ValueNotifier<bool>(false);
  final SharedPreferencesAsync Function() _preferences;
  late final SharedPreferencesAsync _prefs = _preferences();
  final RecipeApi _api;
  Future<void> _tail = Future.value();
  Timer? _poll;
  String? _uid;
  String? _lastToken;
  String _installation = '';
  bool _started = false;

  static String randomId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> start() async {
    if (_started || !NativeTimers.supported) return;
    _started = true;
    _installation = await _prefs.getString('timer_installation') ?? randomId();
    await _prefs.setString('timer_installation', _installation);
    WidgetsBinding.instance.addObserver(this);
    NativeTimers.onLocalChange = localChange;
    NativeTimers.channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await NativeTimers.restore();
      if (call.method == 'tokenChanged') refresh();
    });
    _authSubscription = _accountChanges().listen((uid) {
      signedIn.value = uid != null;
      // Reject the previous account immediately, ahead of pending network work.
      unawaited(
        _configure(
          uid,
          false,
          guardOnly: true,
        ).then((_) => _serial(() => _account(uid))).catchError(_failed),
      );
    });
    _tokenSubscription = _tokenChanges().listen((_) => refresh());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  void _failed(Object error) {
    status.value = error is ApiException ? error.message : 'Timer sharing is waiting for a connection. Your local timer still works.';
  }

  Future<void> _account(String? uid) async {
    if (uid != _currentUid()) return;
    final previous = _uid;
    _uid = uid;
    signedIn.value = uid != null;
    if (previous != _uid && previous != null && _lastToken != null) {
      // Disable native reception first, even if unregistering is offline.
      await _configure(null, false);
      try {
        await _api.request(
          '/me/timer-devices/remove',
          _lastToken!,
          body: {'installation_id': _installation},
        );
      } catch (_) {
        /* Native account matching rejects delayed old pushes. */
      }
    }
    _lastToken = null;
    receiving.value =
        _uid != null && (await _prefs.getBool('receive_timers_$_uid') ?? false);
    await _configure(_uid, receiving.value);
    await NativeTimers.restore();
    if (_uid != null) await _sync();
  }

  Future<void> _configure(String? uid, bool enabled, {bool guardOnly = false}) {
    final actual = _currentUid();
    if (actual != uid) {
      uid = actual;
      enabled = false;
      guardOnly = false;
    }
    return NativeTimers.channel.invokeMethod<void>('configureSync', {
      'account_uid': uid ?? '',
      'installation_id': _installation,
      'receive_timers': enabled,
      'guard_only': guardOnly,
    });
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (_currentUid() == null || _currentUid() != _uid) {
      throw StateError('Account changed');
    }
    final token = await _idToken();
    if (_currentUid() != _uid) throw StateError('Account changed');
    if (token == null) throw StateError('Sign in again');
    _lastToken = token;
    return _api.request(path, token, body: body);
  }

  Future<void> _register() async {
    String? token;
    try {
      token = await _pushToken();
    } catch (_) {
      if (receiving.value) rethrow;
    }
    if (receiving.value && token == null) {
      throw StateError('Push registration is not ready');
    }
    await _request(
      '/me/timer-devices',
      body: {
        'installation_id': _installation,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'push_token': token,
        'receive_timers': receiving.value,
      },
    );
  }

  Future<void> setReceiving(bool enabled) => _serial(() async {
    if (_uid == null) throw StateError('Sign in to receive timers.');
    if (enabled) await _authorizeReceiving();
    final old = receiving.value;
    // Turning off is effective locally even if the server cannot be reached.
    receiving.value = enabled;
    await _prefs.setBool('receive_timers_$_uid', enabled);
    await _configure(_uid, enabled);
    try {
      await _register();
      status.value = null;
      if (enabled) await _sync();
    } catch (error) {
      if (enabled) {
        receiving.value = old;
        await _prefs.setBool('receive_timers_$_uid', old);
        await _configure(_uid, old);
        rethrow;
      }
      status.value = 'Receiving is off on this device. The server will be updated when connected.';
    }
  });

  Future<void> localChange(
    String key,
    DateTime? deadline,
    String? title,
  ) async {
    if (_uid == null || _currentUid() != _uid) return;
    final uid = _uid!;
    final id = key.startsWith('remote:')
        ? key.substring(7)
        : '$_installation:$key';
    await _storage(() async {
      if (_uid != uid) return;
      final pending = await _outbox(uid);
      pending.add({
        'timer_id': id,
        'installation_id': _installation,
        'operation_id': randomId(),
        'cancelled': deadline == null,
        if (deadline != null) 'deadline_ms': deadline.millisecondsSinceEpoch,
        'title': ?title,
      });
      await _prefs.setString('timer_outbox_$uid', jsonEncode(pending));
    });
    refresh();
  }

  Future<List<Map<String, dynamic>>> _outbox(String uid) async {
    final raw = await _prefs.getString('timer_outbox_$uid');
    return raw == null
        ? []
        : (jsonDecode(raw) as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
  }

  Future<void> _apply(Map<String, dynamic> timer) async {
    if (_currentUid() != _uid) return;
    await NativeTimers.channel.invokeMethod<void>('applyRemote', {
      ...timer,
      'account_uid': _uid,
      'target_device': _installation,
    });
  }

  Future<void> _sync() async {
    if (_uid == null || _currentUid() != _uid) return;
    final uid = _uid!;
    status.value = null;
    await _configure(_uid, receiving.value);
    await _register();
    await _storageTail;
    final pending = await _outbox(uid);
    while (pending.isNotEmpty) {
      final operation = pending.first;
      final deadline = operation['deadline_ms'] as int?;
      if (deadline == null ||
          deadline > DateTime.now().millisecondsSinceEpoch) {
        final revision =
            await NativeTimers.channel.invokeMethod<int>('syncRevision', {
              'timer_id': operation['timer_id'],
            }) ??
            0;
        // Persist the expected revision before the request. Retries reuse it.
        operation.putIfAbsent('revision', () => revision);
        await _storage(() async {
          final latest = await _outbox(uid);
          final stored = latest
              .where(
                (item) => item['operation_id'] == operation['operation_id'],
              )
              .firstOrNull;
          if (stored != null) stored['revision'] = operation['revision'];
          await _prefs.setString('timer_outbox_$uid', jsonEncode(latest));
        });
        try {
          final response = await _request('/me/timers', body: operation);
          if (_currentUid() == _uid) {
            await NativeTimers.channel.invokeMethod<void>(
              'recordSyncRevision',
              response['timer'],
            );
          }
          if (response['delivery'] == 'pending') {
            status.value = 'Timer saved. Push delivery is unavailable; other devices will sync when opened.';
          }
        } on ApiException catch (error) {
          if (error.status != 409 &&
              error.status != 404 &&
              error.status != 422) {
            rethrow;
          }
          // Do not overwrite a newer change from another device.
          status.value = error.message;
          if (_currentUid() == _uid) {
            await NativeTimers.channel.invokeMethod<void>(
              'forgetSyncRevision',
              {'timer_id': operation['timer_id']},
            );
          }
        }
      }
      pending.removeAt(0);
      await _storage(() async {
        final latest = await _outbox(uid);
        latest.removeWhere(
          (item) => item['operation_id'] == operation['operation_id'],
        );
        await _prefs.setString('timer_outbox_$uid', jsonEncode(latest));
      });
    }
    final response = await _request('/me/timers');
    for (final row in response['timers'] as List) {
      await _apply(Map<String, dynamic>.from(row));
    }
    await NativeTimers.restore();
  }

  Future<void> syncNow() => _serial(_sync);

  Future<void> dispose() async {
    _started = false;
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await _authSubscription?.cancel();
    await _tokenSubscription?.cancel();
    NativeTimers.onLocalChange = null;
    NativeTimers.channel.setMethodCallHandler(null);
    await _tail;
    await _storageTail;
    _api.close();
  }

  void refresh() {
    if (!_started || _uid == null) return;
    unawaited(syncNow().catchError(_failed));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _poll?.cancel();
    if (state == AppLifecycleState.resumed) {
      refresh();
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
    }
  }
}
