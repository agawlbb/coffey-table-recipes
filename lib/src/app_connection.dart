import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'shopping_socket.dart';

/// One authenticated foreground connection, shared by every app screen.
class AppConnection extends ChangeNotifier with WidgetsBindingObserver {
  AppConnection({
    this.connect = WebSocketChannel.connect,
    this.refreshToken,
    this.networkChanges,
  });
  final WebSocketChannel Function(Uri) connect;
  final Future<String?> Function(bool)? refreshToken;
  final Stream<bool>? networkChanges;
  ShoppingSocket? _socket;
  String _token = '', owner = '';
  bool _observing = false, _backgrounded = false;
  Map<String, dynamic> data = {};
  int? serverTime;
  DateTime? receivedAt;
  final _receivers = <Future<void> Function(Map<String, dynamic>)>{};
  Future<void> _accountTail = Future.value();
  Future<void>? _refreshing;
  bool get connected => _socket?.connected ?? false;

  static String identity(String token) {
    try {
      final parts = token.split('.');
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map;
      if (claims['sub'] is String) {
        return jsonEncode([claims['iss'], claims['aud'], claims['sub']]);
      }
    } catch (_) {}
    return token;
  }

  void addReceiver(Future<void> Function(Map<String, dynamic>) receive) =>
      _receivers.add(receive);
  void removeReceiver(Future<void> Function(Map<String, dynamic>) receive) =>
      _receivers.remove(receive);

  Future<void> open(String token) async {
    final nextOwner = identity(token);
    if (owner != nextOwner) {
      reset();
      owner = nextOwner;
    }
    final changed = _token != token;
    _token = token;
    if (changed && connected) {
      _refreshing ??= _socket!.reauthenticate().whenComplete(
        () => _refreshing = null,
      );
    }
    if (_refreshing != null) await _refreshing;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _socket ??= ShoppingSocket(
      household: '',
      scope: 'app',
      connect: connect,
      networkChanges:
          networkChanges ??
          Connectivity().onConnectivityChanged.map(
            (values) => values.any((v) => v != ConnectivityResult.none),
          ),
      token: (refresh) async {
        if (owner.isEmpty) return '';
        if (refresh) {
          final updated =
              await (refreshToken?.call(true) ??
                  FirebaseAuth.instance.currentUser?.getIdToken(true));
          if (updated != null) _token = updated;
        }
        return _token;
      },
      onTime: (time) {
        serverTime = time;
        receivedAt = DateTime.now();
      },
      onSnapshot: (incoming) async {
        data = {...data, ...incoming};
        for (final receive in _receivers.toList()) {
          await receive(incoming);
        }
      },
    )..addListener(notifyListeners);
    await _socket!.ensureReady();
  }

  Future<Map<String, dynamic>> request(
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) async {
    final expectedOwner = token.isEmpty ? owner : identity(token);
    if (token.isNotEmpty) await open(token);
    if (owner != expectedOwner) throw StateError('Account changed.');
    if (_socket == null) await open('');
    await _socket!.ensureReady();
    if (body == null && path == '/me' && data['account'] is Map) {
      return Map<String, dynamic>.from(data['account'] as Map);
    }
    if (body == null && path == '/me/child-mode' && data['account'] is Map) {
      final account = data['account'] as Map;
      return {
        'enabled': (account['user'] as Map)['child_mode'],
        'people_child_modes': account['people_child_modes'] ?? {},
      };
    }
    final socket = _socket!;
    Future<Map<String, dynamic>> send() => socket.request(path, body: body);
    if (!isAccountPath(path)) return send();
    final result = _accountTail.then((_) => send());
    _accountTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void reset() {
    _socket?.dispose();
    _socket = null;
    _token = '';
    owner = '';
    data = {};
    notifyListeners();
  }

  void reconnect() => _socket?.reconnect();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgrounded = true;
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      reconnect();
    }
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _socket?.dispose();
    super.dispose();
  }
}

final appConnection = AppConnection();
