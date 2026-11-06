import 'app_connection.dart';
import 'client_log.dart';
import 'shopping_socket.dart';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'child_mode.dart';

import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

bool isOfflineFailure(Object error) =>
    error is TimeoutException ||
    error is http.ClientException ||
    (error is FirebaseAuthException && error.code == 'network-request-failed');

bool isTemporaryCommunicationFailure(Object error) =>
    isOfflineFailure(error) ||
    (error is ApiException &&
        [408, 429, 500, 502, 503, 504].contains(error.status));

/// Only use for reads or operations that prepare an unsaved draft.
/// Writes must handle a lost success response without blindly replaying it.
Future<T> retryCommunication<T>(
  Future<T> Function() request, {
  List<Duration> delays = const [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1500),
  ],
  Future<void> Function(Duration) wait = Future<void>.delayed,
  bool Function()? active,
  void Function()? onRetry,
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await request();
    } catch (error) {
      if (!isTemporaryCommunicationFailure(error) ||
          attempt >= delays.length ||
          active?.call() == false) {
        rethrow;
      }
      onRetry?.call();
      final delay = delays[attempt];
      final cooldown = error is ApiException
          ? error.retryAfter ??
                (error.status == 429 ? const Duration(seconds: 30) : null)
          : null;
      await wait(cooldown != null && cooldown > delay ? cooldown : delay);
      if (active?.call() == false) rethrow;
    }
  }
}

final apiBaseUrl = resolveApiBaseUrl(
  override: const String.fromEnvironment('API_BASE_URL'),
);

String resolveApiBaseUrl({String override = ''}) {
  if (override.isNotEmpty) return override;
  return 'https://ctr.coffeybean.com/api/v1';
}

// Keep existing persisted queues when only the production request host changes.
String apiStorageNamespaceFor(String baseUrl) =>
    baseUrl == 'https://ctr.coffeybean.com/api/v1'
    ? 'https://coffeybean.com/CoffeyTableRecipes/api/v1'
    : baseUrl;
final apiStorageNamespace = apiStorageNamespaceFor(apiBaseUrl);

String managedRecipeImageUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      !['coffeybean.com', 'www.coffeybean.com'].contains(uri.host) ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty) {
    return value;
  }
  final match = RegExp(
    r'^/CoffeyTableRecipes/media/(?:recipes|recipe-photos|recipe-illustrations)/((?:[a-f0-9]{48}|[a-f0-9]{64}|[a-z][a-z0-9-]*-ai-v[1-9][0-9]*)\.(?:jpg|png|webp)|category-[1-9][0-9]*\.jpg)$',
  ).firstMatch(uri.path);
  if (match == null) {
    return value;
  }
  return 'https://ctr.coffeybean.com/media/recipes/${match.group(1)}';
}

bool isPublicRecipeRead(String path) =>
    !Uri.parse(path).queryParameters.containsKey('favorite_people') &&
    RegExp(r'^/households/[1-9][0-9]*/recipes(?:/[1-9][0-9]*)?$')
        .hasMatch(Uri.parse(path).path);

class RecipeApi {
  RecipeApi({
    required this.baseUrl,
    http.Client? client,
    this.onServerTime,
    WebSocketChannel Function(Uri)? socketConnect,
    AppConnection? connection,
  }) : _app =
           connection ??
           (client == null && socketConnect == null ? appConnection : null),
       _client = client ?? http.Client(),
       _useSockets = client == null || socketConnect != null,
       _socketConnect = socketConnect ?? WebSocketChannel.connect {
    _app?.addReceiver(_appSnapshot);
    _app?.addListener(_appChanged);
  }
  final AppConnection? _app;
  String? _appOwner;
  bool _appApplied = false, _appConnected = false;
  Future<void> Function(Map<String, dynamic>)? onAppSnapshot;
  AppConnection? get liveConnection => _app;
  Future<void> _appSnapshot(Map<String, dynamic> data) async {
    if (_appOwner != _app?.owner || _closed) return;
    if (_app?.serverTime != null) {
      onServerTime?.call(_app!.serverTime!, _app.receivedAt!);
      onServerClock?.call(_app!.serverTime!);
    }
    if (onAppSnapshot != null ||
        onCookingSnapshot != null ||
        onTimerSnapshot != null) {
      _appApplied = true;
      await onAppSnapshot?.call(data);
      if (data['cooking'] is Map) {
        await onCookingSnapshot?.call(
          Map<String, dynamic>.from(data['cooking'] as Map),
        );
      }
      if (data['timers'] is Map) {
        await onTimerSnapshot?.call(
          Map<String, dynamic>.from(data['timers'] as Map),
        );
      }
    }
  }

  void _appChanged() {
    if (_closed) return;
    final connected = _app?.connected ?? false;
    onConnectionChanged?.call();
    if (connected && !_appConnected) onSocketReady?.call();
    _appConnected = connected;
  }

  final String baseUrl;
  final http.Client _client;
  final void Function(int milliseconds, DateTime receivedAt)? onServerTime;

  final bool _useSockets;
  final WebSocketChannel Function(Uri) _socketConnect;
  final _sockets = <String, ShoppingSocket>{};
  Future<Map<String, dynamic>> Function(
    String path, {
    Map<String, dynamic>? body,
  })?
  householdRequest;
  Future<void> Function(Map<String, dynamic>)? onTimerSnapshot;
  Future<void> Function(Map<String, dynamic>)? onCookingSnapshot;
  void Function(int)? onServerClock;
  void Function()? onSocketReady;
  void Function()? onConnectionChanged;
  bool get socketsReady => _app != null
      ? _app.connected
      : _sockets.isNotEmpty &&
            _sockets.values.every((s) => s.connected && !s.applyingSnapshot);
  String _socketToken = '';
  String _socketIdentity = '';

  // This is connection ownership, not authentication. The server validates
  // every token. A token refresh for the same identity must not abort writes.
  static String _identity(String token) {
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ) as Map;
        if (claims['sub'] is String && (claims['sub'] as String).isNotEmpty) {
          return jsonEncode([claims['iss'], claims['aud'], claims['sub']]);
        }
      }
    } catch (_) {}
    return token;
  }

  Future<String?> Function()? refreshSocketToken;

  void resetSockets() {
    _app?.reset();
    _appOwner = null;
    _appApplied = false;
    for (final socket in _sockets.values) {
      socket.dispose();
    }
    _sockets.clear();
    _socketToken = '';
    _socketIdentity = '';
    onConnectionChanged?.call();
  }

  void reconnectSockets() {
    if (_app != null) {
      _app.reconnect();
      return;
    }
    for (final socket in _sockets.values) {
      socket.reconnect();
    }
  }

  Future<Map<String, dynamic>> _socketRequest(
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) {
    if (_app != null) {
      return _appRequest(path, token, body: body);
    }
    final uri = Uri.parse(path);
    final scope = isAccountPath(path)
        ? 'account'
        : isAiPath(path)
        ? 'ai'
        : uri.path.startsWith('/me/cooking-sessions')
        ? 'cooking'
        : uri.path.startsWith('/me/')
        ? 'timers'
        : uri.path.startsWith('/recipes/')
        ? 'public'
        : 'household';
    if (scope == 'household' && householdRequest != null) {
      return householdRequest!(path, body: body);
    }
    if (scope != 'public') {
      final identity = _identity(token);
      if (_socketIdentity != identity) {
        for (final entry in _sockets.entries.toList()) {
          if (entry.key.startsWith('public/')) continue;
          entry.value.dispose();
          _sockets.remove(entry.key);
        }
        _socketIdentity = identity;
      }
      _socketToken = token;
    }
    final household =
        (scope == 'household' || scope == 'ai') &&
            uri.path.startsWith('/households/')
        ? uri.pathSegments[1]
        : '';
    final key = '$scope/$household';
    final socket = _sockets.putIfAbsent(key, () {
      final created = ShoppingSocket(
        household: household,
        scope: scope,
        connect: _socketConnect,
        token: (refresh) async {
          if (scope == 'public') return '';
          if (refresh) {
            final renewed =
                await (refreshSocketToken?.call() ??
                    FirebaseAuth.instance.currentUser?.getIdToken(true));
            if (renewed != null) _socketToken = renewed;
          }
          return _socketToken;
        },
        networkChanges: Connectivity().onConnectivityChanged.map(
          (results) => results.any((r) => r != ConnectivityResult.none),
        ),
        onSnapshot: (data) async {
          if (scope == 'timers') await onTimerSnapshot?.call(data);
          if (scope == 'cooking') await onCookingSnapshot?.call(data);
        },
        onTime: (time) {
          onServerTime?.call(time, DateTime.now());
          onServerClock?.call(time);
        },
        onReady: () => onSocketReady?.call(),
      );
      created.addListener(() => onConnectionChanged?.call());
      return created;
    });
    return socket.request(path, body: body);
  }

  Future<void> connect(String token) async {
    if (_app == null) return;
    _appOwner = AppConnection.identity(token);
    await _app.open(token);
    if (!_appApplied && _app.data.isNotEmpty) await _appSnapshot(_app.data);
  }

  Future<Map<String, dynamic>> _appRequest(
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) async {
    _appOwner = token.isEmpty ? _app!.owner : AppConnection.identity(token);
    if (token.isNotEmpty) await _app!.open(token);
    if (!_appApplied && _app!.data.isNotEmpty) await _appSnapshot(_app.data);
    return _app!.request(path, token, body: body);
  }

  Future<Map<String, dynamic>> request(
    String path,
    String token, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
    void Function(int received, int? total)? onProgress,
  }) async {
    try {
      return await _performRequest(
        path,
        token,
        body: body,
        timeout: timeout,
        onProgress: onProgress,
      );
    } catch (error, stack) {
      clientLog.record(
        'api',
        body == null ? 'read_failed' : 'write_failed',
        path: path,
        error: error,
        stack: stack,
        status: error is ApiException ? error.status : null,
        code: error is ApiException ? error.code : null,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _performRequest(
    String path,
    String token, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
    void Function(int received, int? total)? onProgress,
  }) async {
    if (body != null) requireChildModeWrite(path);
    if (_closed) throw StateError('API closed');
    if (_useSockets &&
        (isVpsDataPath(path) || isAiPath(path) || isAccountPath(path))) {
      return body == null
          ? retryCommunication(
              () => _socketRequest(path, token),
              active: () => !_closed,
            )
          : _socketRequest(path, token, body: body);
    }
    if (body == null) {
      return retryCommunication(
        () =>
            _requestOnce(path, token, timeout: timeout, onProgress: onProgress),
        active: () => !_closed,
      );
    }
    return _requestOnce(path, token, body: body, timeout: timeout);
  }

  bool _closed = false;
  DateTime? _limitedUntil;

  Future<Map<String, dynamic>> _requestOnce(
    String path,
    String token, {
    Map<String, dynamic>? body,
    required Duration timeout,
    void Function(int received, int? total)? onProgress,
  }) async {
    final remaining = _limitedUntil?.difference(DateTime.now());
    if (remaining != null && remaining > Duration.zero) {
      throw ApiException(
        429,
        'Updates are temporarily paused. We’ll try again shortly.',
        retryAfter: remaining,
      );
    }
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final http.Response response;
    if (onProgress != null && body == null) {
      response = await (() async {
        final request = http.Request('GET', uri)..headers.addAll(headers);
        final stream = await _client.send(request);
        var received = 0;
        return http.Response.fromStream(
          http.StreamedResponse(
            stream.stream.map((bytes) {
              received += bytes.length;
              onProgress(received, stream.contentLength);
              return bytes;
            }),
            stream.statusCode,
            headers: stream.headers,
            reasonPhrase: stream.reasonPhrase,
          ),
        );
      })().timeout(timeout);
    } else {
      response =
          await (body == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(timeout);
    }
    final serverTime = int.tryParse(response.headers['x-ctr-time-ms'] ?? '');
    if (serverTime != null) onServerTime?.call(serverTime, DateTime.now());
    Duration? retryAfter;
    if (response.statusCode == 429) {
      retryAfter = rateLimitDelay(response.headers['retry-after']);
      _limitedUntil = DateTime.now().add(retryAfter);
    }
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      // Proxies and hosting failures can return HTML instead of API JSON.
      // Preserve the HTTP status, without showing that page or its contents.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data?['error'];
      final message = error is Map ? error['message'] : null;
      throw ApiException(
        response.statusCode,
        message is String && message.trim().isNotEmpty
            ? message
            : response.statusCode == 401
            ? 'Please sign in again.'
            : response.statusCode == 429
            ? 'Updates are temporarily paused. We’ll try again shortly.'
            : response.statusCode == 408 || response.statusCode == 504
            ? 'The recipe service took too long to respond. Please try again.'
            : 'The recipe service could not complete the request (HTTP ${response.statusCode}). Please try again.',
        code: error is Map ? error['code'] as String? : null,
        retryAfter: retryAfter,
      );
    }
    if (data == null) {
      throw ApiException(
        502,
        'The recipe service returned an unreadable response. Please try again.',
      );
    }
    return data;
  }

  Future<String> health() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('The server returned ${response.statusCode}.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'ok') throw Exception('Unexpected server response.');
    return body['service'] as String;
  }

  void close() {
    _app?.removeReceiver(_appSnapshot);
    _app?.removeListener(_appChanged);
    _closed = true;
    for (final socket in _sockets.values) {
      socket.dispose();
    }
    _sockets.clear();
    _client.close();
  }
}

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code, this.retryAfter});
  final Duration? retryAfter;
  final String? code;
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Retry-After can be a number of seconds or an HTTP date.
Duration rateLimitDelay(String? header, {DateTime? now}) {
  final seconds = int.tryParse(header?.trim() ?? '');
  if (seconds != null && seconds >= 0) {
    return Duration(seconds: seconds < 1 ? 1 : seconds);
  }
  final match = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(header?.trim() ?? '');
  if (match != null) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months.indexOf(match[2]!) + 1;
    if (month > 0) {
      final date = DateTime.utc(
        int.parse(match[3]!),
        month,
        int.parse(match[1]!),
        int.parse(match[4]!),
        int.parse(match[5]!),
        int.parse(match[6]!),
      );
      final delay = date.difference(now ?? DateTime.now().toUtc());
      return delay > Duration.zero ? delay : const Duration(seconds: 1);
    }
  }
  return const Duration(seconds: 30);
}
