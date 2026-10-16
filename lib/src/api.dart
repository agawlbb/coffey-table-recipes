import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

bool isOfflineFailure(Object error) =>
    error is TimeoutException ||
    error is http.ClientException ||
    (error is FirebaseAuthException && error.code == 'network-request-failed');

final apiBaseUrl = resolveApiBaseUrl(
  override: const String.fromEnvironment('API_BASE_URL'),
);

String resolveApiBaseUrl({String override = ''}) {
  if (override.isNotEmpty) return override;
  return 'https://coffeybean.com/CoffeyTableRecipes/api/v1';
}

bool isPublicRecipeRead(String path) =>
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
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response =
        await (body == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(timeout);
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
            : response.statusCode == 408 || response.statusCode == 504
            ? 'The recipe service took too long to respond. Please try again.'
            : 'The recipe service could not complete the request (HTTP ${response.statusCode}). Please try again.',
        code: error is Map ? error['code'] as String? : null,
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

  void close() => _client.close();
}

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code});
  final String? code;
  final int status;
  final String message;
  @override
  String toString() => message;
}
