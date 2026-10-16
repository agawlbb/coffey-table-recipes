import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coffey_table_recipes/src/api.dart';

void main() {
  for (final status in [401, 406, 502, 504]) {
    test(
      'HTML failure preserves HTTP $status without leaking the page',
      () async {
        final api = RecipeApi(
          baseUrl: 'https://example.test',
          client: MockClient(
            (_) async => http.Response(
              '<html>private gateway diagnostics</html>',
              status,
            ),
          ),
        );
        addTearDown(api.close);
        await expectLater(
          api.request('/recipe-import', 'test-token', body: {}),
          throwsA(
            isA<ApiException>()
                .having((e) => e.status, 'status', status)
                .having(
                  (e) => e.message,
                  'safe message',
                  isNot(contains('private gateway')),
                ),
          ),
        );
      },
    );
  }
  for (final response in ['[]', 'null', '<html>not JSON</html>']) {
    test(
      'invalid success response is a readable service error: $response',
      () async {
        final api = RecipeApi(
          baseUrl: 'https://example.test',
          client: MockClient((_) async => http.Response(response, 200)),
        );
        addTearDown(api.close);
        await expectLater(
          api.request('/recipe-import', 'test-token', body: {}),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 502)),
        );
      },
    );
  }
  test('JSON error with unexpected structure still preserves status', () async {
    final api = RecipeApi(
      baseUrl: 'https://example.test',
      client: MockClient(
        (_) async => http.Response('{"error":"unstructured"}', 503),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.request('/recipe-import', 'test-token', body: {}),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 503)),
    );
  });

  test('all platforms default to the hosted HTTPS API', () {
    expect(
      resolveApiBaseUrl(),
      'https://coffeybean.com/CoffeyTableRecipes/api/v1',
    );
  });
  test('an explicit API override supports local development', () {
    expect(
      resolveApiBaseUrl(override: 'http://10.0.2.2/CoffeyTableRecipes/api/v1'),
      'http://10.0.2.2/CoffeyTableRecipes/api/v1',
    );
  });
  test(
    'authenticated creation includes token and JSON without client user IDs',
    () async {
      final api = RecipeApi(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer firebase-id-token');
          expect(request.headers['Content-Type'], 'application/json');
          expect(request.body, '{"name":"Our table","person_name":"Alice"}');
          return http.Response(
            '{"household":{"id":"1","name":"Our table","role":"owner"}}',
            201,
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.request(
        '/households',
        'firebase-id-token',
        body: {'name': 'Our table', 'person_name': 'Alice'},
      );
      expect((result['household'] as Map)['role'], 'owner');
    },
  );
  test(
    'authorization errors retain their status for token refresh handling',
    () async {
      final api = RecipeApi(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"message":"Please sign in again."}}',
            401,
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.request('/me', 'expired-token'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
    },
  );
  test(
    'health uses the configured API URL and validates the response',
    () async {
      final api = RecipeApi(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/health');
          return http.Response(
            '{"status":"ok","service":"Coffey Table Recipes"}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      expect(await api.health(), 'Coffey Table Recipes');
    },
  );
  test('server failures do not report a healthy connection', () async {
    final api = RecipeApi(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );
    addTearDown(api.close);
    await expectLater(api.health(), throwsException);
  });
}
