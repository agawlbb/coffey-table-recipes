import 'ai_progress.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

const shoppingSocketUrl = String.fromEnvironment(
  'SHOPPING_SOCKET_URL',
  defaultValue: 'wss://ctr.coffeybean.com/shopping',
);

bool isShoppingPath(String path) =>
    RegExp(r'^/households/[1-9][0-9]*/shopping-list(?:/sync-request)?$')
        .hasMatch(path);

/// Account setup has no household selection and requires a Firebase ID token.
bool isAccountPath(String path) => RegExp(
  r'^/(?:me(?:/verification-email|/child-mode)?|admin/users/[1-9][0-9]*/reset-child-mode|households|households/[1-9][0-9]*/people/[1-9][0-9]*/invitations|invitations/[1-9][0-9]*/respond)$',
).hasMatch(Uri.parse(path).path);

bool isAiPath(String path) => RegExp(
  r'^/(?:households/[1-9][0-9]*/(?:recipe-import|recipe-photo|recipe-category|category-image|recipes/[1-9][0-9]*/variation)|admin/parent-categories(?:/[1-9][0-9]*/category-image)?)$',
).hasMatch(Uri.parse(path).path);

bool isVpsDataPath(String path) {
  final route = Uri.parse(path).path;
  return RegExp(r'^/recipes/[1-9][0-9]*$').hasMatch(route) ||
      RegExp(r'^/me/(?:timers|timer-devices(?:/remove)?)$').hasMatch(route) ||
      RegExp(
        r'^/households/[1-9][0-9]*/(?:snapshot|name|people(?:/me/name)?|restaurants|recipe-blank|shopping-list(?:/sync-request)?|meal-plan(?:/(?:ingredients|history|pairings/[1-9][0-9]*))?|recipes(?:/deleted|/[1-9][0-9]*(?:/(?:edit-options|share|favorites|attach|delete|restore))?)?)$',
      ).hasMatch(route);
}

/// The durable repository owns edits; this connection owns transport only.
class ShoppingSocket extends ChangeNotifier {
  ShoppingSocket({
    required this.household,
    required this.token,
    required this.onSnapshot,
    this.onTime,
    this.scope = 'shopping',
    this.onReady,
    this.connect = WebSocketChannel.connect,
    this.url = shoppingSocketUrl,
    Stream<bool>? networkChanges,
  }) {
    _network = networkChanges?.distinct().listen((available) {
      if (available) {
        // The first online event reports current state; it is not a network
        // change. Do not cancel an opening socket or an in-flight write.
        if (_networkAvailable != null) reconnect();
      } else {
        _lost();
      }
      _networkAvailable = available;
    }, onError: (Object _) {}); // Socket retries still work without OS events.
  }

  final String household;
  final String scope;
  final Future<String?> Function(bool refresh) token;
  final Future<void> Function(Map<String, dynamic>) onSnapshot;
  final void Function(int milliseconds)? onTime;
  final void Function()? onReady;
  final WebSocketChannel Function(Uri) connect;
  final String url;
  bool? _networkAvailable;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<bool>? _network;
  Timer? _retry, _heartbeat, _renew;
  Completer<void>? _ready;
  final _progress = <String, void Function(String, int)>{};
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Future<void> _incoming = Future.value();
  bool connected = false, _closed = false, _opening = false;
  int _sequence = 0, _attempt = 0, _generation = 0;
  DateTime _lastReceived = DateTime.now();

  void start() {
    if (!_closed && !_opening && _channel == null) {
      _retry?.cancel();
      unawaited(_open());
    }
  }

  void reconnect() {
    if (_closed) return;
    _lost();
    _attempt = 0;
    _retry?.cancel();
    start();
  }

  Future<void> _open() async {
    _opening = true;
    final generation = ++_generation;
    final ready = _ready = Completer<void>();
    // Startup may have no caller waiting; errors are still surfaced to requests.
    unawaited(ready.future.catchError((Object _) {}));
    try {
      final credential = await token(_attempt > 0)
          .timeout(const Duration(seconds: 10));
      if (_closed || generation != _generation) return;
      if (credential == null) throw ApiException(401, 'Please sign in again.');
      final channel = connect(Uri.parse(url));
      _channel = channel;
      _subscription = channel.stream.listen(
        (dynamic message) {
          _incoming = _incoming
              .then((_) async {
                if (generation == _generation && !_closed) {
                  await _receive(message, generation);
                }
              })
              .catchError((Object _) {
                if (generation == _generation) _lost();
              });
        },
        onDone: () {
          if (generation == _generation) _lost();
        },
        onError: (Object _) {
          if (generation == _generation) _lost();
        },
      );
      await channel.ready.timeout(const Duration(seconds: 10));
      if (_closed || generation != _generation) return;
      _send({
        'type': 'auth',
        'token': credential,
        'household_id': household.isEmpty ? null : household,
        'scope': scope,
      });
      await ready.future.timeout(
        Duration(seconds: scope == 'household' ? 90 : 20),
      );
      if (_closed || generation != _generation) return;
      _lastReceived = DateTime.now();
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        if (DateTime.now().difference(_lastReceived) >
            const Duration(seconds: 60)) {
          _lost();
        } else {
          _send({'type': 'ping'});
        }
      });
      _renew = Timer(const Duration(minutes: 45), _lost);
    } catch (_) {
      if (!_closed && generation == _generation) _lost();
    } finally {
      if (generation == _generation) _opening = false;
    }
  }

  void _send(Map<String, dynamic> message) =>
      _channel?.sink.add(jsonEncode({'v': 1, ...message}));

  Future<void> _receive(dynamic raw, int generation) async {
    final message = Map<String, dynamic>.from(jsonDecode(raw as String) as Map);
    _lastReceived = DateTime.now();
    if (message['server_time_ms'] is int) {
      onTime?.call(message['server_time_ms'] as int);
    }
    final type = message['type'];
    if (type == 'progress') {
      final callback = _progress[message['id']];
      if (callback != null && message['message'] is String) {
        callback(
          message['message'] as String,
          message['elapsed_seconds'] as int? ?? 0,
        );
      }
    } else if (type == 'error') {
      final details = message['error'] as Map?;
      final error = ApiException(
        message['status'] as int? ?? 503,
        details?['message'] as String? ?? 'Data synchronization paused.',
        code: details?['code'] as String?,
      );
      final pending = _pending.remove(message['id']);
      if (pending != null) pending.completeError(error);
      if (message['id'] == null || [401, 403, 404].contains(error.status)) {
        _lost(error);
      }
    } else if (type == 'ready' || type == 'snapshot') {
      if ((message['household_id'] ?? '') != household) {
        throw const FormatException('Wrong household');
      }
      await onSnapshot(Map<String, dynamic>.from(message['data'] as Map));
      if (_closed || generation != _generation || _channel == null) return;
      if (type == 'ready') {
        connected = true;
        _attempt = 0;
        if (!(_ready?.isCompleted ?? true)) _ready!.complete();
        notifyListeners();
        onReady?.call();
      }
    } else if (type == 'response') {
      _pending
          .remove(message['id'])
          ?.complete(Map<String, dynamic>.from(message['data'] as Map));
    }
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (_closed) throw StateError('Data connection closed');
    if (scope == 'account'
        ? !isAccountPath(path) || household.isNotEmpty
        : scope == 'ai'
        ? (!isAiPath(path) ||
              (path.startsWith('/households/') &&
                  !path.startsWith('/households/$household/')) ||
              (path.startsWith('/admin/') && household.isNotEmpty))
        : scope == 'shopping'
        ? (!path.startsWith('/households/$household/shopping-list') ||
              !isShoppingPath(path))
        : !isVpsDataPath(path) ||
              (scope == 'household' &&
                  !path.startsWith('/households/$household/')) ||
              (scope == 'timers' && !path.startsWith('/me/')) ||
              (scope == 'public' &&
                  !RegExp(r'^/recipes/[1-9][0-9]*$').hasMatch(path))) {
      throw ArgumentError('Data path outside this connection');
    }
    start();
    await _ready!.future.timeout(
      Duration(seconds: scope == 'household' ? 90 : 20),
    );
    if (!connected) {
      throw _connectionLost();
    }
    final id = '${++_sequence}';
    final response = Completer<Map<String, dynamic>>();
    _pending[id] = response;
    final progress = Zone.current[aiProgressZoneKey];
    if (progress is void Function(String, int)) _progress[id] = progress;
    _send({'type': 'request', 'id': id, 'path': path, 'body': ?body});
    try {
      return await response.future.timeout(
        Duration(
          seconds: scope == 'ai' || body?['source_type'] == 'blank'
              ? 615
              : scope == 'account'
              ? 90
              : scope == 'household'
              ? 90
              : 20,
        ),
      );
    } finally {
      _pending.remove(id);
      _progress.remove(id);
    }
  }

  void _lost([Object? failure]) {
    ++_generation;
    _opening = false;
    _incoming = Future.value();
    connected = false;
    _heartbeat?.cancel();
    _renew?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    _channel = null;
    final error = failure ?? _connectionLost();
    if (!(_ready?.isCompleted ?? true)) _ready!.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    _progress.clear();
    if (!_closed) {
      notifyListeners();
      _retry?.cancel();
      _retry = Timer(
        Duration(seconds: math.min(5, 1 << math.min(_attempt++, 3))),
        start,
      );
    }
  }

  ApiException _connectionLost() => ApiException(
    503,
    scope == 'account'
        ? 'The connection to the account service was interrupted. Please try again.'
        : 'Data synchronization disconnected.',
    code: 'connection_lost',
  );

  @override
  void dispose() {
    _closed = true;
    unawaited(_network?.cancel());
    _retry?.cancel();
    _lost();
    super.dispose();
  }
}
