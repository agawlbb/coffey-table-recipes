import 'client_log.dart';
import 'local_data.dart';
import 'local_sqlite.dart';

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
import 'notification_preferences.dart';

final cookingSessions = CookingSessions();
final cookingRouteObserver = RouteObserver<PageRoute<dynamic>>();

typedef CookingRequest = Future<Map<String, dynamic>> Function(
  String path, {
  Map<String, dynamic>? body,
});

class CookingSessionsScope extends InheritedWidget {
  const CookingSessionsScope({
    super.key,
    required this.sessions,
    required super.child,
  });
  final CookingSessions sessions;
  static CookingSessions of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CookingSessionsScope>()
          ?.sessions ??
      cookingSessions;
  @override
  bool updateShouldNotify(CookingSessionsScope oldWidget) =>
      sessions != oldWidget.sessions;
}

class CookingSessions extends ChangeNotifier with WidgetsBindingObserver {
  CookingSessions({
    CookingRequest? request,
    this._preferences,
    this.storage,
    String? installation,
    this._accountChanges,
    this._registerDevice,
  }) : _testRequest = request,
       installation = installation ?? '';
  final CookingRequest? _testRequest;
  final LocalSqlite? storage;
  LocalData? _local;
  String? _boundUid;
  Future<void>? _initializingLocal;
  Future<void> bindLocal(LocalData local, String uid) async {
    if (identical(local, _local)) return;
    await _initializingLocal;
    final previous = _local;
    if (previous != null) {
      final saved = await previous.cached('/me/cooking-sessions');
      if (saved != null && await local.cached('/me/cooking-sessions') == null) {
        await local.acceptCooking(saved);
      }
      await local.importChanges(previous.pendingChanges);
      previous.removeListener(_localChanged);
      if (_boundUid == null) previous.dispose();
    }
    _local = local;
    _boundUid = uid;
    if (_started) await _migrateTimers(local, uid);
    local.addListener(_localChanged);
    local.onAcknowledged = _acknowledged;
    _localChanged();
  }

  void _releaseLocal() {
    _local?.removeListener(_localChanged);
    if (_boundUid == null) _local?.dispose();
    _local = null;
    _boundUid = null;
  }

  final Future<void> Function()? _registerDevice;
  final Stream<String?>? _accountChanges;
  String? _lastToken;
  final SharedPreferencesAsync? _preferences;
  late final SharedPreferencesAsync _prefs =
      _preferences ?? SharedPreferencesAsync();
  final _api = RecipeApi(baseUrl: apiBaseUrl);
  String installation;
  String? _uid;
  bool _started = false, _foreground = true, _loaded = false, _disposed = false;
  String? visibleSession;
  String? error;
  int _generation = 0;
  int _serverOffset = 0;
  DateTime get now => DateTime.now().add(Duration(milliseconds: _serverOffset));
  final List<Map<String, dynamic>> sessions = [];
  final Set<String> offered = {};
  Timer? _presence;
  StreamSubscription<String?>? _auth;
  StreamSubscription<String>? _tokens;
  Future<void> _nativeTail = Future.value();
  bool get isSynchronized =>
      available && (_testRequest != null || _api.socketsReady);
  Future<void> _openLocal() {
    if (_local != null) return _initializingLocal ?? Future.value();
    return _initializingLocal ??= _initializeLocal().whenComplete(
      () => _initializingLocal = null,
    );
  }

  Future<void> _initializeLocal() async {
    final local = LocalData(
      key: '$apiStorageNamespace|${_uid ?? installation}|cooking',
      fetch: (path) => _request(path),
      send: (path, body) => _request(path, body: body),
      readStore: storage?.read ?? readLocalSqlite,
      writeStore: storage?.write ?? writeLocalSqlite,
    );
    _local = local;
    local.connected = () =>
        !_disposed && (_testRequest != null || _api.socketsReady);
    local.onSendError = (_, e) => _failed(e);
    local.addListener(_localChanged);
    local.onAcknowledged = _acknowledged;
    if (_started) await _migrateTimers(local, _uid);
    _localChanged();
  }

  Future<void> _migrateTimers(LocalData local, String? uid) async {
    final old = await _prefs.getString('cooking_outbox_$uid');
    await local.cached('/me/cooking-sessions');
    if (old != null) {
      for (final item in jsonDecode(old) as List) {
        if (!local.containsOperation(item['operation_id'] as String)) {
          await local.save('/me/cooking-sessions/${item['session_id']}/timer', {
            ...item['body'] as Map,
            'operation_id': item['operation_id'],
            'installation_id': installation,
          });
        }
      }
      await _prefs.remove('cooking_outbox_$uid');
    }
  }

  void _acknowledged(Map<String, dynamic> entry) {
    if (_disposed ||
        !(entry['path'] as String).startsWith('/me/cooking-sessions') ||
        !NativeTimers.supported ||
        _testRequest != null) {
      return;
    }
    unawaited(
      NativeTimers.channel
          .invokeMethod<void>('acknowledgeAction', {
            'account_uid': _uid,
            'operation_id': entry['id'],
          })
          .catchError((Object error) => _failed(error)),
    );
  }

  void _localChanged() {
    final local = _local;
    if (local == null || _disposed) return;
    try {
      final data = local.readView('/me/cooking-sessions');
      sessions
        ..clear()
        ..addAll(
          (data['sessions'] as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
      _loaded = true;
    } on StateError {
      return;
    }
    unawaited(reconcileStartAlarms().catchError(_failed));
    notifyListeners();
  }

  void _invalidateSync() {
    // Route presence can change during build; invalidate state immediately,
    // then notify mounted UI outside the build stack.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  bool get available => _testRequest != null || _uid != null;
  static String randomId() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Map<String, dynamic>? session(String id) =>
      sessions.where((s) => s['id'] == id).firstOrNull;
  bool joined(Map<String, dynamic> s) =>
      (s['joined_devices'] as List? ?? []).contains(installation);
  List<Map<String, dynamic>> get invitations => sessions
      .where(
        (s) =>
            !joined(s) &&
            !offered.contains(s['id']) &&
            (s['invited'] == true || s['open_elsewhere'] == true),
      )
      .toList();

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (_testRequest != null) {
      NativeTimers.onLocalChange = timerChanged;
      if (installation.isEmpty) installation = randomId();
      WidgetsBinding.instance.addObserver(this);
      _auth = _accountChanges?.listen((uid) => unawaited(_account(uid)));
      await _openLocal();
      return;
    }
    installation = await _prefs.getString('timer_installation') ?? randomId();
    await _prefs.setString('timer_installation', installation);
    WidgetsBinding.instance.addObserver(this);
    _api.onConnectionChanged = () {
      if (!_disposed) notifyListeners();
    };
    _api.refreshSocketToken = () async =>
        FirebaseAuth.instance.currentUser?.getIdToken(true);
    _api.onCookingSnapshot = (data) async {
      if (_uid != FirebaseAuth.instance.currentUser?.uid) return;
      await accept(data);
    };
    _api.onServerClock = (milliseconds) =>
        _serverOffset = milliseconds - DateTime.now().millisecondsSinceEpoch;
    _api.onSocketReady = () => unawaited(_flush().catchError(_failed));
    NativeTimers.onLocalChange = timerChanged;
    if (NativeTimers.supported) {
      NativeTimers.channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') {
          await _readNativeActions();
          await NativeTimers.restore();
          unawaited(_flush().catchError(_failed));
        }
        if (call.method == 'tokenChanged') await _register();
      });
    }
    if (NativeTimers.supported) {
      _tokens = FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => unawaited(_register().catchError(_failed)),
      );
    }
    _auth =
        (_accountChanges ??
                FirebaseAuth.instance.authStateChanges().map(
                  (user) => user?.uid,
                ))
            .listen((uid) => unawaited(_account(uid)));
    _presence = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_foreground && visibleSession != null) {
        unawaited(presence(visibleSession!, true).catchError(_failed));
      }
    });
  }

  void _failed(Object e) {
    if (_disposed) return;
    clientLog.record(
      'cooking',
      'sync_failed',
      error: e,
      status: e is ApiException ? e.status : null,
      code: e is ApiException ? e.code : null,
    );
    if (isTemporaryCommunicationFailure(e)) {
      notifyListeners();
      return;
    }
    error = e is ApiException ? e.message : 'Could not update cooking.';
    notifyListeners();
  }

  Future<void> _account(String? uid) async {
    final previous = _uid;
    final oldToken = _lastToken;
    _lastToken = null;
    if (previous != null &&
        previous != uid &&
        oldToken != null &&
        _testRequest == null) {
      unawaited(() async {
        final cleanup = RecipeApi(baseUrl: apiBaseUrl);
        try {
          await cleanup.request(
            '/me/timer-devices/remove',
            oldToken,
            body: {'installation_id': installation},
          );
        } catch (_) {
          /* Native account guards reject any delayed background updates. */
        } finally {
          cleanup.close();
        }
      }());
    }
    final generation = ++_generation;
    _uid = uid;
    _loaded = false;
    visibleSession = null;
    sessions.clear();
    _feedback.clear();
    offered.clear();
    if (_boundUid != uid) _releaseLocal();
    if (previous != null || uid == null) _api.resetSockets();
    notifyListeners();
    try {
      await _configure();
      if (generation != _generation || uid == null) return;
      await _openLocal();

      try {
        await _register();
      } catch (e) {
        if (generation == _generation) _failed(e);
      }
      if (generation != _generation) return;
      if (_testRequest != null) {
        await refresh();
      } else {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) await _api.connect(token);
        await _readNativeActions();
        await _flush();
      }
    } catch (e) {
      if (generation == _generation) _failed(e);
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (_testRequest != null) {
      final generation = _generation;
      final result = await _testRequest(path, body: body);
      if (generation != _generation) throw StateError('Account changed.');
      return result;
    }
    final uid = _uid;
    final generation = _generation;
    if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Sign in again.');
    }
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || generation != _generation) {
      throw StateError('Account changed.');
    }
    _lastToken = token;
    final result = await _api.request(
      path,
      token,
      body: body,
      timeout: path.endsWith('/cooking-plan')
          ? const Duration(seconds: 570)
          : const Duration(seconds: 20),
    );
    if (generation != _generation) throw StateError('Account changed.');
    return result;
  }

  Future<void> refreshDeviceRegistration() => _register();

  Future<void> setInvitationNotifications(bool enabled) =>
      _register(invitations: enabled);

  Future<void> _registrationTail = Future.value();

  Future<void> _register({bool? invitations}) {
    final next = _registrationTail
        .catchError((Object _) {})
        .then((_) => _registerNow(invitations: invitations));
    _registrationTail = next;
    return next;
  }

  Future<void> _registerNow({bool? invitations}) async {
    if (_disposed) return;
    if (_registerDevice != null) return _registerDevice();
    if (_uid == null || !NativeTimers.supported || _testRequest != null) return;
    await notificationPreferences.read();
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      /* WebSocket cooking still works. */
    }
    await _request(
      '/me/timer-devices',
      body: {
        'installation_id': installation,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'push_token': token,
        'receive_cooking_invitations':
            invitations ??
            notificationPreferences.values['invitations'] ??
            true,
        'receive_timers': false,
      },
    );
    // Keep preference changes and background registration in the same queue.
    if (invitations != null) {
      await notificationPreferences.set('invitations', invitations);
    }
  }

  Future<void> _configure() async {
    if (!NativeTimers.supported || _testRequest != null) return;
    final uid = _uid;
    final loaded = _loaded;
    final ids = sessions.where(joined).map((s) => s['id']).toList();
    final next = _nativeTail.catchError((Object _) {}).then((_) async {
      if (uid != _uid) return;
      await NativeTimers.channel.invokeMethod<void>('configureSync', {
        'account_uid': uid ?? '',
        'installation_id': installation,
        'receive_timers': false,
        'clock_offset_ms': _serverOffset,
        if (loaded) 'session_ids': ids,
      });
    });
    _nativeTail = next;
    await next;
  }

  Future<void> accept(
    Map<String, dynamic> data, {
    bool confirmed = true,
  }) async {
    final generation = _generation;
    if (!available) return;
    if (data['sessions'] is! List) {
      throw const FormatException('Invalid cooking snapshot');
    }
    final incoming = (data['sessions'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await _openLocal();
    await _local!.acceptCooking({'sessions': incoming});
    _loaded = true;
    error = null;
    if (visibleSession != null && session(visibleSession!) == null) {
      visibleSession = null;
    }
    notifyListeners();
    await _configure();
    await reconcileStartAlarms();
    if (generation != _generation ||
        !NativeTimers.supported ||
        _testRequest != null) {
      return;
    }
    for (final s in [
      ...sessions,
      ...(data['ended_sessions'] as List? ?? []).cast<Map>(),
    ]) {
      if (!(s['joined_devices'] as List? ?? []).contains(installation)) {
        continue;
      }
      for (final t in s['timers'] as List? ?? []) {
        if (generation != _generation) return;
        try {
          await NativeTimers.channel.invokeMethod<void>('applyRemote', {
            ...Map<String, dynamic>.from(t as Map),
            'account_uid': _uid,
            'target_device': installation,
          });
        } catch (_) {
          error = 'Could not update a cooking alarm. Check alarm permissions.';
        }
      }
    }
    await NativeTimers.restore();
    await reconcileStartAlarms();
  }

  Future<void> importNativeActions(List<Map<String, dynamic>> actions) async {
    await _openLocal();
    for (final action in actions) {
      if (action['account_uid'] != _uid ||
          action['installation_id'] != installation) {
        continue;
      }
      if (_local!.containsOperation(action['operation_id'] as String)) continue;
      await change(
        '${action['session_id']}',
        'timer',
        Map<String, dynamic>.from(action['body'] as Map),
        operation: action['operation_id'] as String,
      );
    }
  }

  Future<void> _readNativeActions() async {
    if (!NativeTimers.supported || _testRequest != null || _uid == null) return;
    final generation = _generation;
    final rows =
        await NativeTimers.channel.invokeListMethod<dynamic>(
          'pendingActions',
        ) ??
        [];
    if (generation != _generation) return;
    await importNativeActions(
      rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
    );
  }

  Future<void> refresh() async {
    if (!available) return;
    _invalidateSync();
    final generation = _generation;
    try {
      await _readNativeActions();
      final data = await _request('/me/cooking-sessions');
      if (generation != _generation) return;
      await accept(data);
      await _flush();
    } catch (e) {
      if (generation == _generation) _failed(e);
    }
  }

  Future<Map<String, dynamic>> change(
    String id,
    String action,
    Map<String, dynamic> body, {
    String? operation,
  }) async {
    await _openLocal();
    final result = await _local!.save('/me/cooking-sessions/$id/$action', {
      ...body,
      'installation_id': installation,
      'operation_id': operation ?? randomId(),
    });
    await reconcileStartAlarms();
    return Map<String, dynamic>.from(result['session'] as Map);
  }

  Future<void> _permissions() async {
    if (!NativeTimers.supported || _testRequest != null) return;
    try {
      await NativeTimers.channel.invokeMethod<void>('requestTimerPermissions');
      unawaited(_register().catchError(_failed));
    } catch (_) {
      error = 'Allow alarms in device settings to mirror cooking timers.';
      notifyListeners();
    }
  }

  final Map<String, List<Map<String, dynamic>>> _feedback = {};
  List<Map<String, dynamic>> feedbackMessages(String id) => _feedback[id] ?? [];

  Future<Map<String, dynamic>> planRequest(
    String household,
    Map<String, dynamic> body,
  ) async {
    if (!available) throw ApiException(401, 'Sign in to plan cooking.');
    final generation = _generation;
    if (body['action'] == 'feedback') await _flush();
    if (generation != _generation) throw StateError('Account changed.');
    final result = await _request(
      '/households/$household/cooking-plan',
      body: {...body, 'installation_id': installation},
    );
    if (generation != _generation) throw StateError('Account changed.');
    await _openLocal();
    if (generation != _generation) throw StateError('Account changed.');
    final updated = Map<String, dynamic>.from(result['session'] as Map);
    await _local!.acceptCooking({
      'sessions': [...sessions.where((s) => s['id'] != updated['id']), updated],
    });
    if (result['messages'] is List) {
      _feedback['${updated['id']}'] = (result['messages'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    await reconcileStartAlarms();
    return result;
  }

  DateTime? planStart(Map<String, dynamic> s) {
    if (s['combined'] != true ||
        s['started_at'] != null ||
        s['ended_at'] != null) {
      return null;
    }
    final steps = (s['recipe'] as Map)['steps'] as List;
    if (steps.isEmpty) return null;
    final offset = steps
        .map((e) => (e['offset_seconds'] as num).toInt())
        .reduce(min);
    return DateTime.fromMillisecondsSinceEpoch(
      (s['dinner_at'] as num).toInt() + offset * 1000,
    );
  }

  String startAlarmKey(String id) => 'plan-start:${_uid ?? 'test'}:$id';
  bool hasStartAlarm(String id) => NativeTimers.active.value.any(
    (a) =>
        a['key'] == startAlarmKey(id) &&
        (a['deadline'] as num) > DateTime.now().millisecondsSinceEpoch,
  );
  Future<void> setStartAlarm(String id) async {
    final generation = _generation;
    final original = session(id);
    if (original == null) throw ApiException(404, 'Cooking session ended.');
    if (!NativeTimers.supported) {
      throw ApiException(422, 'Start alarms are available on Android and iOS.');
    }
    if (!joined(original)) await join(id);
    await _configure();
    await NativeTimers.channel.invokeMethod<void>('requestTimerPermissions');
    if (generation != _generation) throw StateError('Account changed.');
    final current = session(id);
    final start = current == null ? null : planStart(current);
    if (start == null || !start.isAfter(now)) {
      throw ApiException(422, 'Start time has passed.');
    }
    final key = startAlarmKey(id);
    await NativeTimers.schedule(
      key,
      start.subtract(Duration(milliseconds: _serverOffset)),
      '${(current!['recipe'] as Map)['title']} · Start cooking',
    );
    if (generation != _generation) {
      await NativeTimers.cancel(key);
      throw StateError('Account changed.');
    }
    await reconcileStartAlarms();
    notifyListeners();
  }

  Future<void> removeStartAlarm(String id) async {
    await NativeTimers.cancel(startAlarmKey(id));
    notifyListeners();
  }

  Future<void> _alarmTail = Future.value();
  Future<void> reconcileStartAlarms() {
    final next = _alarmTail.catchError((Object _) {}).then((_) async {
      if (!NativeTimers.supported || !_loaded) return;
      for (final alarm in List<Map<String, dynamic>>.from(
        NativeTimers.active.value,
      )) {
        final key = '${alarm['key']}';
        if (!key.startsWith('plan-start:')) continue;
        final id = key.split(':').last;
        final s = key == startAlarmKey(id) ? session(id) : null;
        final start = s == null ? null : planStart(s);
        if (start == null || !start.isAfter(now)) {
          await NativeTimers.cancel(key);
        } else {
          final deadline = start.subtract(
            Duration(milliseconds: _serverOffset),
          );
          if ((deadline.millisecondsSinceEpoch - (alarm['deadline'] as num))
                  .abs() >
              1000) {
            await NativeTimers.schedule(
              key,
              deadline,
              '${(s!['recipe'] as Map)['title']} · Start cooking',
            );
          }
        }
      }
    });
    _alarmTail = next;
    return next;
  }

  Future<Map<String, dynamic>> create(
    String household,
    Map<String, dynamic> recipe,
  ) async {
    await _permissions();
    await _openLocal();
    final id = randomId();
    final result = await _local!.save('/me/cooking-sessions', {
      'session_id': id,
      'household_id': household,
      'recipe_id': '${recipe['id']}',
      'installation_id': installation,
      'operation_id': id,
      '_local_recipe': recipe,
    });
    return Map<String, dynamic>.from(result['session'] as Map);
  }

  Future<Map<String, dynamic>> join(String id) async {
    await _permissions();
    return change(id, 'join', {});
  }

  Future<void> check(String id, String step, bool checked) async {
    final s = session(id);
    if (s == null) return;
    await change(id, 'step', {'step_id': step, 'checked': checked});
  }

  Future<void> presence(String id, bool open) async {
    if (session(id) == null || !joined(session(id)!)) return;
    if (open) {
      visibleSession = id;
    } else if (visibleSession == id) {
      visibleSession = null;
    }
    await change(id, 'presence', {'open': open});
  }

  Future<void> end(String id) async {
    final alarms = NativeTimers.active.value
        .where((t) => '${t['key']}'.startsWith('remote:session:$id:'))
        .toList();
    for (final alarm in alarms) {
      await NativeTimers.cancel(alarm['key'] as String);
    }
    await change(id, 'end', {});
  }

  Future<List<Map<String, dynamic>>> people(String id) async {
    final result = await _request('/me/cooking-sessions/$id/people');
    return (result['people'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> share(String id, String person) async {
    await change(id, 'share', {'person_id': person});
  }

  List<Map<String, dynamic>> timers(String id) {
    final result = <String, Map<String, dynamic>>{
      for (final t in session(id)?['timers'] as List? ?? [])
        '${t['action_id']}': Map<String, dynamic>.from(t as Map),
    };
    return result.values.toList();
  }

  void reportError(String message) {
    error = message;
    if (!_disposed) notifyListeners();
  }

  Future<void> timerChanged(
    String key,
    DateTime? deadline,
    String? title,
  ) async {
    final match = RegExp(r'^remote:session:([a-f0-9]{32}):(.+)$')
        .firstMatch(key);
    if (match == null || !available) return;
    final id = match[1]!;
    final action = match[2]!;
    final s = session(id);
    if (s == null || !joined(s)) return;
    final local = NativeTimers.active.value
        .where((row) => row['key'] == key)
        .firstOrNull;
    final uid = _uid;
    final generation = _generation;
    final body = {
      'action_id': action,
      'extension_seconds': (local?['extension_seconds'] as num?)?.toInt() ?? 0,
      if (local?['extending'] == true) 'extend': true,
      'cancelled': deadline == null,
      'deadline_ms': deadline
          ?.add(Duration(milliseconds: _serverOffset))
          .millisecondsSinceEpoch,
    };
    if (uid != _uid || generation != _generation) return;
    await change(id, 'timer', body);
  }

  Future<void> _flush() async {
    await _openLocal();
    await _local!.synchronize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    final visible = visibleSession;
    if (_foreground) {
      offered.clear();
      if (_uid != null) unawaited(_register().catchError(_failed));
      unawaited(_readNativeActions().then((_) => _flush()).catchError(_failed));
      if (visible != null) {
        unawaited(presence(visible, true).catchError(_failed));
      }
    } else if (visible != null) {
      unawaited(presence(visible, false).catchError(_failed));
      visibleSession = visible; // Remember the route for foreground return.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _presence?.cancel();
    _releaseLocal();
    unawaited(_auth?.cancel());
    unawaited(_tokens?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _api.close();
    if (_started) {
      NativeTimers.onLocalChange = null;
      NativeTimers.channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
