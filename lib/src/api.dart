import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

final apiBaseUrl = resolveApiBaseUrl(
  isWeb: kIsWeb,
  pageUrl: kIsWeb ? Uri.base : null,
  override: const String.fromEnvironment('API_BASE_URL'),
);

String resolveApiBaseUrl({
  required bool isWeb,
  Uri? pageUrl,
  String override = '',
}) {
  if (override.isNotEmpty) return override;
  return isWeb
      ? pageUrl!.resolve('/CoffeyTableRecipes/api/v1').toString()
      : 'http://10.0.2.2/CoffeyTableRecipes/api/v1';
}

class RecipeApi {
  RecipeApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> request(
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response =
        await (body == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 20));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data['error'] as Map<String, dynamic>?;
      throw ApiException(
        response.statusCode,
        error?['message'] as String? ?? 'The request failed.',
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
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}
