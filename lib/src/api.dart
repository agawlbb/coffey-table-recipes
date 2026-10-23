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
  return 'https://coffeybean.com/CoffeyTableRecipes/api/v1';
}

bool isPublicRecipeRead(String path) =>
    !Uri.parse(path).queryParameters.containsKey('favorite_people') &&
    RegExp(r'^/households/[1-9][0-9]*/recipes(?:/[1-9][0-9]*)?$')
        .hasMatch(Uri.parse(path).path);

class RecipeApi {
  RecipeApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> request(
    String path,
    String token, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
    void Function(int received, int? total)? onProgress,
  }) async {
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
    _closed = true;
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
