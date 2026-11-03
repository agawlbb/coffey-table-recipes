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
    String? installation,
    this._accountChanges,
  }) : _testRequest = request,
       installation = installation ?? '';
  final CookingRequest? _testRequest;
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
  Future<void> _tail = Future.value();
  Future<void> _nativeTail = Future.value();
  Future<void> _storageTail = Future.value();
  Future<void> _saveOutbox(String? uid) {
    final contents = jsonEncode(_outbox);
    final next = _storageTail
        .catchError((Object _) {})
        .then((_) => _prefs.setString('cooking_outbox_$uid', contents));
    _storageTail = next;
    return next;
  }

  List<Map<String, dynamic>> _outbox = [];
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
      final raw = await _prefs.getString('cooking_outbox_null');
      _outbox = raw == null
          ? []
          : (jsonDecode(raw) as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
      return;
    }
    installation = await _prefs.getString('timer_installation') ?? randomId();
    await _prefs.setString('timer_installation', installation);
    WidgetsBinding.instance.addObserver(this);
    _api.refreshSocketToken = () async =>
        FirebaseAuth.instance.currentUser?.getIdToken(true);
    _api.onCookingSnapshot = (data) async {
      if (_uid != FirebaseAuth.instance.currentUser?.uid) return;
      await accept(data);
    };
    _api.onServerClock = (milliseconds) =>
        _serverOffset = milliseconds - DateTime.now().millisecondsSinceEpoch;
    _api.onSocketReady = () => unawaited(refresh());
    NativeTimers.onLocalChange = timerChanged;
    if (NativeTimers.supported) {
      NativeTimers.channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') await NativeTimers.restore();
        if (call.method == 'tokenChanged') await refresh();
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
    error = e is ApiException
        ? e.message
        : 'Cooking sync paused. Check your connection.';
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
    offered.clear();
    _outbox = [];
    _api.resetSockets();
    notifyListeners();
    try {
      await _configure();
      if (generation != _generation || uid == null) return;
      final raw = await _prefs.getString('cooking_outbox_$uid');
      if (generation != _generation) return;
      _outbox = raw == null
          ? []
          : (jsonDecode(raw) as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();

      await _register();
      await refresh();
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
    final result = await _api.request(path, token, body: body);
    if (generation != _generation) throw StateError('Account changed.');
    return result;
  }

  Future<void> _register() async {
    if (_uid == null || !NativeTimers.supported || _testRequest != null) return;
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
        'receive_timers': false,
      },
    );
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

  Future<void> accept(Map<String, dynamic> data) async {
    final generation = _generation;
    if (!available) return;
    _loaded = true;
    final incoming = (data['sessions'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    // A delayed response must not replace a newer session snapshot.
    for (var i = 0; i < incoming.length; i++) {
      final old = session('${incoming[i]['id']}');
      if (old != null &&
          (old['revision'] as num) > (incoming[i]['revision'] as num)) {
        incoming[i] = old;
      }
    }
    sessions
      ..clear()
      ..addAll(incoming);
    if (visibleSession != null && session(visibleSession!) == null) {
      visibleSession = null;
    }
    notifyListeners();
    await _configure();
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
        if (_outbox.any(
          (o) =>
              o['session_id'] == s['id'] &&
              o['body']['action_id'] == t['action_id'],
        )) {
          continue;
        }
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
  }

  Future<void> refresh() async {
    if (!available) return;
    final generation = _generation;
    try {
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
    final result = await _request(
      '/me/cooking-sessions/$id/$action',
      body: {
        ...body,
        'installation_id': installation,
        'operation_id': operation ?? randomId(),
      },
    );
    final updated = Map<String, dynamic>.from(result['session'] as Map);
    if (updated['ended_at'] != null) {
      await accept({
        'sessions': sessions.where((s) => s['id'] != id).toList(),
        'ended_sessions': [updated],
      });
    } else {
      await accept({
        'sessions': [...sessions.where((s) => s['id'] != id), updated],
      });
    }
    return updated;
  }

  Future<void> _permissions() async {
    if (!NativeTimers.supported || _testRequest != null) return;
    try {
      await NativeTimers.channel.invokeMethod<void>('requestTimerPermissions');
      await _register();
    } catch (_) {
      error = 'Allow alarms in device settings to mirror cooking timers.';
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> create(
    String household,
    Map<String, dynamic> recipe,
  ) async {
    await _permissions();
    final id = randomId();
    final result = await _request(
      '/me/cooking-sessions',
      body: {
        'session_id': id,
        'household_id': household,
        'recipe_id': '${recipe['id']}',
        'installation_id': installation,
        'operation_id': id,
      },
    );
    final s = Map<String, dynamic>.from(result['session'] as Map);
    await accept({
      'sessions': [...sessions, s],
    });
    return s;
  }

  Future<Map<String, dynamic>> join(String id) async {
    await _permissions();
    return change(id, 'join', {});
  }

  Future<void> check(String id, String step, bool checked) async {
    final s = session(id);
    if (s == null) return;
    await change(id, 'step', {
      'step_id': step,
      'checked': checked,
      'revision': (s['step_revisions'] as Map?)?[step] ?? 0,
    });
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
    for (final op in _outbox.where((o) => o['session_id'] == id)) {
      final body = op['body'] as Map;
      final action = '${body['action_id']}';
      result[action] = {
        ...?result[action],
        'action_id': action,
        'cancelled': body['cancelled'],
        'extension_seconds': body['extension_seconds'] ?? 0,
        if (body['deadline_ms'] != null) 'deadline_ms': body['deadline_ms'],
      };
    }
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
    final timer = (s['timers'] as List? ?? [])
        .where((t) => '${t['action_id']}' == action)
        .firstOrNull;
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
      'revision':
          _outbox
                  .where(
                    (o) =>
                        o['session_id'] == id &&
                        o['body']['action_id'] == action,
                  )
                  .lastOrNull?['body']['revision']
              is int
          ? (_outbox
                        .where(
                          (o) =>
                              o['session_id'] == id &&
                              o['body']['action_id'] == action,
                        )
                        .last['body']['revision']
                    as int) +
                1
          : timer?['revision'] ?? 0,
    };
    final operation = {
      'session_id': id,
      'operation_id': randomId(),
      'body': body,
    };
    _outbox.add(operation);
    notifyListeners();
    await _saveOutbox(uid);
    if (generation != _generation) return;
    unawaited(_flush().catchError(_failed));
  }

  Future<void> _flush() {
    final generation = _generation;
    final uid = _uid;
    final next = _tail.catchError((Object _) {}).then((_) async {
      while (generation == _generation && _outbox.isNotEmpty) {
        final op = _outbox.first;
        try {
          await change(
            op['session_id'] as String,
            'timer',
            Map<String, dynamic>.from(op['body'] as Map),
            operation: op['operation_id'] as String,
          );
        } on ApiException catch (e) {
          if (![404, 409, 422].contains(e.status)) rethrow;
          error = e.message;
        }
        if (generation != _generation) return;
        _outbox.remove(op);
        await _saveOutbox(uid);
        if (generation == _generation) {
          await accept({'sessions': List<Map<String, dynamic>>.from(sessions)});
        }
      }
    });
    _tail = next;
    return next;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    final visible = visibleSession;
    if (_foreground) {
      offered.clear();
      if (_uid != null) unawaited(_register().catchError(_failed));
      _api.reconnectSockets();
      unawaited(refresh());
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
